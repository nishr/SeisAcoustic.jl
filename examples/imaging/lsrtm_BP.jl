using SeisPlot, SeisAcoustic

# ==============================================================================
#             read physical model
function lsrtm_BP()

  dir_work = joinpath(homedir(), "Desktop/lsrtm");

  path_rho = joinpath(dir_work, "physical_model/rho.rsf");
  path_vel = joinpath(dir_work, "physical_model/vel.rsf");

  # read the physical model
  (hdr_rho, rho) = read_RSdata(path_rho);
  (hdr_vel, vel) = read_RSdata(path_vel);

  # # cropped model for imaging
  vel = vel[1:2:1350,650:2:3700];
  rho = rho[1:2:1350,650:2:3700];
  vel = model_smooth(vel, 15);

  rho1 = copy(rho); rho1 .= minimum(rho);
  vel1 = copy(vel); vel1 .= vel[1];


  SeisPlotTX(vel, dx=0.0125, dy=0.0125, yticks=0:2:8, xticks=0:2:19, hbox=1.3*3, wbox=3.7*3, xlabel="X (km)", ylabel="Z (km)", cmap="rainbow", vmin=minimum(vel), vmax=maximum(vel));
  cbar = colorbar(); cbar.set_label("km/s"); tight_layout(); savefig("/Users/wenlei/Desktop/vel.pdf"); close();

  SeisPlotTX(rho, dx=0.0125, dy=0.0125, yticks=0:2:8, xticks=0:2:19, hbox=1.3*3, wbox=3.7*3, xlabel="X (km)", ylabel="Z (km)", cmap="rainbow", vmin=minimum(rho), vmax=maximum(rho));
  cbar = colorbar(); cbar.set_label("g/cm^3"); tight_layout(); savefig("/Users/wenlei/Desktop/rho.pdf"); close();

  # vertical and horizontal grid size
  dz = 6.25; dx = 6.25;

  # time step size and maximum modelling length
  dt = 0.0007; tmax = 6.0;

  # top boundary condition
  free_surface = false;
  data_format  = Float32;
  order        = 5;

  # tdparams for generating observations
  fidiff_hete = TdParams(rho, vel, free_surface, dz, dx, dt, tmax;
                    data_format=data_format, order=order);

  # tdparams for removing direct arrival
  fidiff_homo = TdParams(rho1, vel1, free_surface, dz, dx, dt, tmax;
                         data_format=data_format, order=order);

  # tdparams for imaging
  fidiff = TdParams(rho1, vel, free_surface, dz, dx, dt, tmax;
                    data_format=data_format, order=order);


  # initialize a source
  # isz = 2; isx = fidiff.nx;
  # src = Source(isz, isx, fidiff; amp=100000, fdom=20, type_flag="miniphase");

  # # vector of source
  isx = collect(40 : 12 : fidiff.nx-50); isz = 2*ones(length(isx));
  src = get_multi_sources(isz, isx, fidiff; amp=100000, fdom=20, type_flag="miniphase");

  # generate observed data
  irx = collect(1: 2 : fidiff.nx);
  irz = 2 * ones(Int64, length(irx));

  dir_obs        = joinpath(dir_work, "observations");
  dir_sourceside = joinpath(dir_work, "sourceside");

  # prepare observations and sourceside wavefield
  get_reflections(dir_obs, irz, irx, src, fidiff_hete, fidiff_homo);
  get_wavefield_bound(dir_sourceside, src, fidiff);

  born_params = (irz=irz, irx=irx, dir_sourceside=dir_sourceside, fidiff=fidiff, normalization_flag=true, mute_index=10);
  (x, his) = cgls(born_approximation, dir_obs; dir_work=dir_work, op_params=born_params,
                  d_axpby=recordings_axpby!, m_axpby=image_axpby!, d_norm=recordings_norm, m_norm=l2norm_rsf);
end

lsrtm_BP();

# download the data
scp wgao1@saig-ml.physics.ualberta.ca:/home/wgao1/Desktop/lsrtm/iterations/iteration_1.rsf /Users/wenlei/Desktop/
scp wgao1@saig-ml.physics.ualberta.ca:/home/wgao1/Desktop/lsrtm/sourceside/normalization.rsf /Users/wenlei/Desktop/

(hdr, m) = read_RSdata("/Users/wenlei/Desktop/iteration_1.rsf")
(hdr, s) = read_RSdata("/Users/wenlei/Desktop/normalization.rsf")
s = reshape(s, 675, 1526);
m = reshape(m, 675, 1526);
m .= m .* s;
m1= laplace_filter(m);

p2 = copy(rho)
for i2 = 1 : size(p2,2)
    for i1 = 1 : size(p2, 1)-1
        p2[i1,i2] = (p2[i1+1,i2]-p2[i1,i2]) / (p2[i1+1,i2]+p2[i1,i2])
    end
end

SeisPlotTX(m, cmap="gray", hbox=6.75, wbox=15.2);
SeisPlotTX(s, cmap="rainbow", hbox=6.75, wbox=15.2, vmax=maximum(s), vmin=minimum(s));
SeisPlotTX(m1, cmap="gray", hbox=6.75, wbox=15.2, pclip=96);
SeisPlotTX(p2, cmap="gray", hbox=6.75, wbox=15.2);
SeisPlotTX(vel, cmap="rainbow", hbox=6.75, wbox=15.2, vmax=maximum(vel), vmin=minimum(vel));



# ==============================================================================
#      generate reflected shot recordings, the direct arrival is removed
# ==============================================================================
function get_reflected_wave()

root = "/Users/wenlei/Desktop/data/marmousi"
path = joinpath(root, "vel.bin")
(hdr, vel) = read_USdata(path)

(nz, nx) = size(vel);
rho = ones(vel);
npml = 20; free_surface = false;

dz = 2.0f0; dx = 2.0f0;
dt = Float32(2.2e-4); fdom = 35.f0;
tmax = 2.0f0;
phi  = PhysicalModel(nz, nx, npml, free_surface, dz, dx, dt, tmax, fdom, rho, vel);
fidMtx1 = FiniteDiffMatrix(phi);

# the finite-difference stencil for remove direct arrival
vmin = minimum(vel); fill!(phi.vel, vmin);
fidMtx2 = FiniteDiffMatrix(phi);

# receiver location
irx = collect(1:2:nx); irz = 1*ones(Int64, length(irx));

# specify source location
isx = collect(10:10:nx-5)
ns  = length(isx)
isz = 2 * ones(Int64, ns)
ot  = zeros(phi.data_format, ns);
amp = phi.data_format(1.e5) * ones(phi.data_format, ns);

# parameters for forward modeling
path =  join([path, "/observations/obs"]);
par = Vector{Dict}(ns)
for i = 1 : ns
    src = Source(isz[i], isx[i], ot[i], amp[i], phi)
    tmp = isx[i]
    path_obs = join([path "_" "$tmp" ".bin"])
    par[i] = Dict(:phi=>phi, :src=>src, :fidMtx1=>fidMtx1, :fidMtx2=>fidMtx2,
                  :irz=>irz, :irx=>irx, :path_obs=>path_obs)
end

pmap(wrap_get_reflections, par)

end

get_reflected_wave()

# examine the recordings
path = "/Users/wenlei/Desktop/data/marmousi/observation/obs_"
i = 990
path_in = join([path "$i" ".bin"]);
(hdr, d) = read_USdata(path_in);
SeisPlot(d, cmap="seismic", pclip=95);

# upload
scp -r /Users/wenlei/Desktop/tmp_LSRTM/physical_model/ wgao1@saig-ml.physics.ualberta.ca:/home/wgao1/lsrtm

# download
scp -r wgao1@saig-ml.physics.ualberta.ca:/home/wgao1/Desktop/lsrtm/iterations /Users/wenlei/Desktop/


# # ==============================================================================
# #             convert physical model of SU to RSF
# work_dir = joinpath(homedir(), "Desktop/tmp_LSRTM");
#
# path_rho = joinpath(work_dir, "physical_model/rho.su");
# path_vel = joinpath(work_dir, "physical_model/vel.su");
#
# num_samples = 1911;
# num_traces  = 5395;
# trace = zeros(Float32, num_samples);
# vel   = zeros(Float32, num_samples, num_traces);
# rho   = zeros(Float32, num_samples, num_traces);
#
# fid_vel = open(path_vel, "r");
# fid_rho = open(path_rho, "r");
# idx = [1];
# for i = 1 : num_traces
#     skip(fid_vel, 240)
#     skip(fid_rho, 240)
#
#     read!(fid_vel, trace)
#     copyto!(vel, idx[1], trace, 1, num_samples)
#
#     read!(fid_rho, trace)
#     copyto!(rho, idx[1], trace, 1, num_samples)
#     idx[1] = idx[1] + num_samples
# end
# close(fid_vel);
# close(fid_rho);
#
# # save the physical model
# hdr_rho = RegularSampleHeader(rho; o1=0., d1=6.25, label1="Z", unit1="m",
#                                    o2=0., d2=6.25, label2="X", unit2="m",
#                                    title="density model");
#
# hdr_vel = RegularSampleHeader(vel; o1=0., d1=6.25, label1="Z", unit1="m",
#                                    o2=0., d2=6.25, label2="X", unit2="m",
#                                    title="velocity model");
#
# path_rho = joinpath(work_dir, "physical_model/rho.rsf");
# path_vel = joinpath(work_dir, "physical_model/vel.rsf");
# write_RSdata(path_rho, hdr_rho, rho);
# write_RSdata(path_vel, hdr_vel, vel);

# ==============================================================================
#    get the bounds of source-side wavefield and the source intensity
# ==============================================================================
function get_sourceside_wavefield_bound()

  root = "/Users/wenlei/Desktop/data/marmousi"
  # root = "/home/wgao1/Data/marmousi"
  path = joinpath(root, "marmousi_smooth.bin")
  (hdr, vel) = read_USdata(path)


  (nz, nx) = size(vel);
  rho = ones(vel);
  npml = 20; free_surface = false;


  dz = 2.0f0; dx = 2.0f0;
  dt = Float32(2.2e-4); fdom = 35.f0;
  tmax = 2.0f0;
  phi  = PhysicalModel(nz, nx, npml, free_surface, dz, dx, dt, tmax, fdom, rho, vel);
  fidMtx = FiniteDiffMatrix(phi);


  # receiver location
  irx = collect(1:2:nx); irz = 1*ones(Int64, length(irx));

  # specify source location
  isx = collect(10:10:nx-5)
  ns  = length(isx)
  isz = 2 * ones(Int64, ns)
  ot  = zeros(phi.data_format, ns);
  amp = phi.data_format(1.e5) * ones(phi.data_format, ns);

  # receiver location
  path1 = joinpath(root, "boundary/bnd");
  path2 = joinpath(root, "precondition/str");

  # parameters for forward modeling
par = Vector{Dict}(ns)
for i = 1 : ns
    src = Source(isz[i], isx[i], ot[i], amp[i], phi)
    tmp = isx[i]
    path_bnd = join([path1 "_" "$tmp" ".bin"])
    path_str = join([path2 "_" "$tmp" ".bin"])
    par[i]   = Dict(:phi=>phi, :src=>src, :fidMtx=>fidMtx, :path_bnd=>path_bnd, :path_str=>path_str)
end

path_pre = joinpath(root, "precondition/pre.bin")
wrap_get_wavefield_bound(path_pre, par)

end
get_sourceside_wavefield_bound()


# ==============================================================================
#   RTM or LSRTM or PLSRTM
# ==============================================================================
function RTM(option)

  # root = "/home/wgao1/Data/marmousi"
  root = "/Users/wenlei/Desktop/data/marmousi"
  path = joinpath(root, "marmousi_smooth.bin")
  (hdr, vel0) = read_USdata(path)
  vel = model_smooth(vel0, 20);

  (nz, nx) = size(vel);
  rho = ones(vel);
  npml = 20; free_surface = false;

  dz = 2.0f0; dx = 2.0f0;
  dt = Float32(2.2e-4); fdom = 35.f0;
  tmax = 2.0f0;
  phi  = PhysicalModel(nz, nx, npml, free_surface, dz, dx, dt, tmax, fdom, rho, vel);
  fidMtx = FiniteDiffMatrix(phi);
  fidMtxT= RigidFiniteDiffMatrix(phi);

  # receiver location
  irx = collect(1:2:nx); irz = 1*ones(Int64, length(irx));

  # specify source location
  isx = collect(10:10:nx-5)
  ns  = length(isx)
  isz = 2 * ones(Int64, ns)
  ot  = zeros(phi.data_format, ns);
  amp = phi.data_format(1.e5) * ones(phi.data_format, ns);

  # chop the top part of the model
  model_window = build_model_window(50, 10, phi);

  # intermediate result
  path_bnd = joinpath(root, "boundary/bnd");
  path_pre = joinpath(root, "precondition/pre.bin");
  path_obs = joinpath(root, "observation/obs");
  path_m   = joinpath(root, "model/m.bin");
  path_fwd = joinpath(root, "forward/fwd");
  path_adj = joinpath(root, "adjoint/adj");

  # parameters for forward modeling
  par = pack_parameter_born(phi, isz, isx, ot, amp,
                            irz, irx, fidMtx, fidMtxT, model_window,
                            path_bnd, path_pre, path_obs, path_m, path_fwd, path_adj);


  b = Vector{String}(ns)
  for i = 1 : ns
      b[i] = par[i][:path_obs]
  end

  # RTM
  if option == 1
     wrap_RTM(b, params=par)

  # LSRTM
  elseif option == 2
     path = joinpath(root, "PCGLS")
     (x, convergence) = CGLS(wrap_preconditioned_born_approximation, b;
                        path=path, params=par, print_flag=true)
  end


end
