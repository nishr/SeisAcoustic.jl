using SeisPlot, SeisAcoustic, LinearAlgebra, DSP

# homogeneous velocity and density model
nz = 101; nx = 301;
vel = 3000 * ones(nz, nx);  # m/s
vel[51:end,:] .= 3500;  # m/s
rho = 2000 * ones(nz, nx);  # kg/m^3

# number of PML layers
npml = 20;

# top boundary condition
free_surface = true;   #(pml or free_surface)

# vertical and horizontal grid size
dz = 10; dx = 10;

# time step size and maximum modelling length
dt = 0.001; tmax = 2.0;  # use second as unit

# organize these parameters into a structure
params = TdParams(rho, vel, free_surface, dz, dx, dt, tmax;
         data_format=Float32, fd_flag="taylor", order=5, npml=20, apml=900.);

# shows the default value for the keyword parameters
# data_format = (Float32 or Float64)
# fd_flag     = ("taylor" or "ls")
# order       = 2 - 10 if we use "ls" to compute the FD coefficients
#             = 2 - n  if we use "taylor" expansion to compute FD coefficients

# initialize a source
src = Source(2, 150, params; ot=0.0, fdom=20.0,
      type_flag="ricker", amp=100000, location_flag="index");

# initialize multi-sources
# isx = collect(5:60:295); ns=length(isx); isz = 2*ones(ns);
# ot  = 0.5*rand(ns);
# srcs = get_multi_sources(isz, isx, params; amp=100000, ot=ot, fdom=15);

# initialize recordings
irx = collect(1:2:params.nx);
irz = 2 * ones(length(irx));
rec = Recordings(irz, irx, params);

# forward modeling of simultaneous sources
multi_step_forward!(rec, src , params);
SeisPlotTX(rec, pclip=98);


# ==============================================================================
#                   dot-product test for the adjoint wavefield
# ==============================================================================
# test the one-step adjoint operator
spt1_f = Snapshot(params);
spt2_f = Snapshot(params);
spt1_b = Snapshot(params);
spt2_b = Snapshot(params);

# initialize spt1_f with random number
for ix = 1 : params.Nx
    amp = 1.0
    col_idx = (ix-1) * params.Nz

    for iz = 1 : params.Nz
        idx= col_idx + iz
        spt1_f.vz[idx] = amp * randn(); spt2_b.vz[idx] = amp * randn()
        spt1_f.vx[idx] = amp * randn(); spt2_b.vx[idx] = amp * randn()
        spt1_f.pz[idx] = amp * randn(); spt2_b.pz[idx] = amp * randn()
        spt1_f.px[idx] = amp * randn(); spt2_b.px[idx] = amp * randn()
    end
end

# temporary variables
tmp    = zeros(params.data_format, params.Nz * params.Nx);
tmp_z1 = zeros(params.data_format, params.Nz);
tmp_z2 = zeros(params.data_format, params.Nz);
tmp_x1 = zeros(params.data_format, params.Nx);
tmp_x2 = zeros(params.data_format, params.Nx);

# nt-step forward
nt = 1000
for it = 1 : nt
    one_step_forward!(spt2_f, spt1_f, params, tmp_z1, tmp_z2, tmp_x1, tmp_x2);
    copy_snapshot!(spt1_f, spt2_f);
end

# nt-step adjoint
for it = 1 : nt
    one_step_adjoint!(spt1_b, spt2_b, params, tmp, tmp_z1, tmp_z2, tmp_x1, tmp_x2);
    copy_snapshot!(spt2_b, spt1_b);
end

# inner product
tmp1 = (dot(spt1_f.vz, spt1_b.vz) + dot(spt1_f.vx, spt1_b.vx)
      + dot(spt1_f.pz, spt1_b.pz) + dot(spt1_f.px, spt1_b.px))

tmp2 = (dot(spt2_f.vz, spt2_b.vz) + dot(spt2_f.vx, spt2_b.vx)
      + dot(spt2_f.pz, spt2_b.pz) + dot(spt2_f.px, spt2_b.px))

(tmp1-tmp2) / tmp1

# test multi-step adjoint operator
# forward modelling
irx = collect(1:2:params.nx); irz = 2 * ones(length(irx));
rec1 = Recordings(irz, irx, params);
multi_step_forward!(rec1, src, params);

# adjoint wavefield
w    = ricker(10.0, params.dt)
hl   = floor(Int64, length(w)/2)
rec2 = Recordings(irz, irx, params);
idx_o= [1]
for i = 1 : rec2.nr
    tmp = conv(randn(params.nt)*1000, w)
    copyto!(rec2.p, idx_o[1], tmp, hl+1, params.nt)
    idx_o[1] = idx_o[1] + params.nt
end
p1 = multi_step_adjoint!(rec2, src, params);

tmp1 = dot(p1, src.p)
tmp2 = dot(vec(rec2.p), vec(rec1.p))
(tmp1-tmp2) / tmp1


# ==============================================================================
#           adjoint Pz = Px in computational area
# ==============================================================================
# generate band-limited random recordings
w   = ricker(12.0, params.dt)
hl  = floor(Int64, length(w)/2)
rec = Recordings(irz, irx, params);
idx_o= [1]

# generate data trace by trace
for i = 1 : rec2.nr
    tmp = conv(randn(params.nt)*1000, w)
    copyto!(rec.p, idx_o[1], tmp, hl+1, params.nt)
    idx_o[1] = idx_o[1] + params.nt
end

# save adjoint pz and px as an 3D cube
path_spt = joinpath(homedir(), "Desktop/snapshot.rsf")
multi_step_adjoint!(path_spt, rec, params; save_flag="snapshot")

# read the adjoint snapshot cube
(hdr, d) = read_RSdata(path_spt);

zl = params.ntop+1; zu = zl + params.nz - 1;
xl = params.npml+1; xu = xl + params.nx - 1;

it = 500
SeisPlotTX(d[zl:zu,xl:xu,3,it], wbox=9, hbox=3, cmap="gray")
SeisPlotTX(d[zl:zu,xl:xu,4,it], wbox=9, hbox=3, cmap="gray")
SeisPlotTX(d[:,:,3,it], wbox=9, hbox=3, cmap="gray")
SeisPlotTX(d[:,:,4,it], wbox=9, hbox=3, cmap="gray")
SeisPlotTX(d[:,:,3,it]-d[:,:,4,it], wbox=9, hbox=3, cmap="gray")
norm(d[zl:zu,xl:xu,3,:] - d[zl:zu,xl:xu,4,:])


# # # ==============================================================================
# # #    test efficiency
# spt1_f = Snapshot(params);
# spt2_f = Snapshot(params);
# spt1_b = Snapshot(params);
# spt2_b = Snapshot(params);
#
# # initialize spt1_f with random number
# for ix = 1 : params.Nx
#     amp = 1.0
#     col_idx = (ix-1) * params.Nz
#
#     for iz = 1 : params.Nz
#         idx= col_idx + iz
#         spt1_f.vz[idx] = amp * randn(); spt1_b.vz[idx] = spt1_f.vz[idx]
#         spt1_f.vx[idx] = amp * randn(); spt1_b.vx[idx] = spt1_f.vx[idx]
#         spt1_f.pz[idx] = amp * randn(); spt1_b.pz[idx] = spt1_f.pz[idx]
#         spt1_f.px[idx] = amp * randn(); spt1_b.px[idx] = spt1_f.px[idx]
#     end
# end
#
# # temporary variables
# tmp_z1 = zeros(params.data_format, params.Nz);
# tmp_z2 = zeros(params.data_format, params.Nz);
# tmp_x1 = zeros(params.data_format, params.Nx);
# tmp_x2 = zeros(params.data_format, params.Nx);
#
# # nt-step forward
# function foo(nt, spt2, spt1, params, tmp_z1, tmp_z2, tmp_x1, tmp_x2)
#
#     for it = 1 : nt
#         one_step_forward!(spt2, spt1, params, tmp_z1, tmp_z2, tmp_x1, tmp_x2)
#         copy_snapshot!(spt1, spt2);
#     end
#     return nothing
# end
#
# function boo(nt, spt2, spt1, params, tmp, tmp_z1, tmp_z2, tmp_x1, tmp_x2)
#
#     for it = 1 : nt
#         one_step_forward_new!(spt2, spt1, params, tmp_z1, tmp_z2, tmp_x1, tmp_x2)
#         copy_snapshot!(spt1, spt2);
#     end
#     return nothing
# end
#
# nt = 1000
# @time foo(nt, spt2_f, spt1_f, params, tmp_z1, tmp_z2, tmp_x1, tmp_x2);
# @time boo(nt, spt2_b, spt1_b, params, tmp, tmp_z1, tmp_z2, tmp_x1, tmp_x2);
