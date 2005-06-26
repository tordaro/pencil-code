! $Id: start.f90,v 1.144 2005-06-26 17:34:13 eos_merger_tony Exp $
!
!***********************************************************************
      program start
!
!  start, to setup initial condition and file structure
!
!-----------------------------------------------------------------------
!  01-apr-01/axel+wolf: coded
!  01-sep-01/axel: adapted to MPI
!
        use Cdata
        use Grid
        use General

        use Mpicomm
        use Sub
        use IO
        use Param_IO
        use Register

        use Global
        use Snapshot
        use Filter
        use Initcond

        use EquationOfState

        use Hydro,        only: init_uu
        use Density,      only: init_lnrho
        use Entropy,      only: init_ss
        use PScalar,      only: init_lncc
        use Chiral,       only: init_chiral
        use Magnetic,     only: init_aa
        use Gravity,      only: init_gg
        use Cosmicray,    only: init_ecr
        use Cosmicrayflux,only: init_fcr
        use Special,      only: init_special
        use Dustdensity,  only: init_nd
        use Dustvelocity, only: init_uud

        use Radiation,    only: init_rad, radtransfer
        use Particles
!
        implicit none

!
!  define parameters
!  The f-array includes auxiliary variables
!  Although they are not necessary for start.f90, idl may want to read them,
!  so we define therefore the full array and write it out.
!
        integer :: i,ifilter,stat
        logical :: lnoerase=.false.
!       logical :: lock=.false.
!       logical :: exist
        real :: x00,y00,z00
!        real, dimension (mx,my,mz,mvar+maux) :: f
!        real, dimension (mx,my,mz,mvar) :: df
!        real, dimension (mx,my,mz) :: xx,yy,zz
        real, allocatable, dimension (:,:,:,:) :: f,df
        real, allocatable, dimension (:,:,:) :: xx,yy,zz
!
        lstart = .true.
!
! Set a flag if colored output has been requested.
!
        inquire(FILE="COLOR", EXIST=ltermcap_color)
!
!  Allocate large arrays. We need to make them allocatable in order to
!  avoid segfaults at 128^3 (7 variables) with Intel compiler on 32-bit
!  Linux boxes. Not clear why they crashed (we _did_ increase stacksize
!  limits), but they did and now don't. Also, the present approach runs
!  up to nx=ny=nz=135 (nx=ny=nz=128 if only xx,yy,zz are made
!  allocatable), but not for even slightly larger grids.
!
        allocate(xx(mx,my,mz)          ,STAT=stat); if (stat>0) call stop_it("Couldn't allocate memory for xx")
        allocate(yy(mx,my,mz)          ,STAT=stat); if (stat>0) call stop_it("Couldn't allocate memory for yy")
        allocate(zz(mx,my,mz)          ,STAT=stat); if (stat>0) call stop_it("Couldn't allocate memory for zz")
        allocate( f(mx,my,mz,mvar+maux),STAT=stat); if (stat>0) call stop_it("Couldn't allocate memory for f ")
        allocate(df(mx,my,mz,mvar)     ,STAT=stat); if (stat>0) call stop_it("Couldn't allocate memory for df")
!
        call register_modules()         ! register modules, etc.
!
!  identify version
!
        if (lroot) call cvs_id( &
             "$Id: start.f90,v 1.144 2005-06-26 17:34:13 eos_merger_tony Exp $")
!
!  set default values: box of size (2pi)^3
!
        xyz0 = (/       -pi,        -pi,       -pi /) ! first corner
        xyz1 = (/impossible, impossible, impossible/) ! last corner
        Lxyz = (/impossible, impossible, impossible/) ! box lengths
        lperi =(/.true.,.true.,.true. /) ! all directions periodic
        lequidist=(/.true.,.true.,.true. /) ! all directions equidistant grid
! dgm
        lshift_origin=(/.false.,.false.,.false./) ! don't shift origin
!
!  Initialize start time
!
        t=0
!
!  read parameters from start.in
!  call also rprint_list, because it writes iuu, ilnrho, iss, and iaa to disk.

        call read_startpars(FILE=.true.)
        call rprint_list(.false.)
!
!  Will we write all slots of f?
!
        if (lwrite_aux) then
          mvar_io = mvar+maux
        else
          mvar_io = mvar
        endif
!
!  print resolution
!
        if (lroot) print*, 'nxgrid,nygrid,nzgrid=',nxgrid,nygrid,nzgrid
!
!  postprocess input parameters
!
        gamma1 = gamma-1.
!
!  I don't think there was a good reason to write param.nml twice (but
!  leave this around for some time [wd; rev. 1.71, 5-nov-2002]
!        call wparam()
!
!  Set up directory names and check whether the directories exist
!
        call directory_names()
!
!  Unfortunately the following test for existence of directory fails under
!  OSF1:
!        inquire(FILE=trim(directory_snap), EXIST=exist)
!        if (.not. exist) &
!             call stop_it('Need directory <' // trim(directory_snap) // '>')
!

!
!  Set box dimensions, make sure Lxyz and xyz1 are in sync.
!  Box defaults to [-pi,pi] for all directions if none of xyz1 or Lxyz are set
!
        do i=1,3
          if (Lxyz(i) == impossible) then
            if (xyz1(i) == impossible) then
              Lxyz(i) = 2*pi    ! default value
            else
              Lxyz(i) = xyz1(i)-xyz0(i)
            endif
          else                  ! Lxyz was set
            if (xyz1(i) /= impossible) then ! both Lxyz and xyz1 are set
              call stop_it('Cannot set Lxyz and xyz1 at the same time')
            endif
          endif
        enddo
        xyz1=xyz0+Lxyz
!
!  abbreviations
!
        x0 = xyz0(1) ; y0 = xyz0(2) ; z0 = xyz0(3)
        Lx = Lxyz(1) ; Ly = Lxyz(2) ; Lz = Lxyz(3)
!
!  check consistency
!
        if (.not.lperi(1).and.nxgrid<2) &
            call stop_it('for nonperiodic: must have nxgrid>1')
        if (.not.lperi(2).and.nygrid<2) &
            call stop_it('for nonperiodic: must have nygrid>1')
        if (.not.lperi(3).and.nzgrid<2) &
            call stop_it('for nonperiodic: must have nzgrid>1')
        if (lperi(1).and.lshift_origin(1)) &
            call stop_it('for periodic: must have lshift_origin=F')
        if (lperi(2).and.lshift_origin(2)) &
            call stop_it('for periodic: must have lshift_origin=F')
        if (lperi(3).and.lshift_origin(3)) &
            call stop_it('for periodic: must have lshift_origin=F')
!
!  Initialise random number generator in processor-dependent fashion for
!  random initial data.
!  Slightly tricky, since setting seed=(/iproc,0,0,0,0,0,0,0,.../)
!  would produce very short-period random numbers with the Intel compiler;
!  so we need to retain most of the initial entropy of the generator. 
!
        call get_nseed(nseed)   ! get state length of random number generator
        call random_seed_wrapper(get=seed(1:nseed))
        seed(1) = -(10+iproc)    ! different random numbers on different CPUs
        call random_seed_wrapper(put=seed(1:nseed))
!
!  generate grid
!
        call construct_grid(x,y,z,dx,dy,dz,x00,y00,z00)
!
!  write grid.dat file
!
        call wgrid(trim(directory)//'/grid.dat')
!
!  write .general file for data explorer
!
          if (lroot) call write_dx_general( &
                            trim(datadir)//'/var.general', &
                            x0-nghost*dx, y0-nghost*dy, z0-nghost*dz)
!
!  as full arrays
!
        xx=spread(spread(x,2,my),3,mz)
        yy=spread(spread(y,1,mx),3,mz)
        zz=spread(spread(z,1,mx),2,my)
!
!  Parameter dependent initialization of module variables and final
!  pre-timestepping setup (must be done before need_XXXX can be used, for
!  example).
!
        call initialize_modules(f,lstarting=.true.)
!
!  Initial conditions: by default, we put f=0 (ss=lnrho=uu=0, etc)
!  alternatively: read existing snapshot and overwrite only some fields
!  by the various procedures below.
!
        if(lread_oldsnap) then
          call rsnap(trim(directory_snap)//'/var.dat',f, mvar)
!
!  default: everything zero
!
        else
          f = 0.
        endif
!
!  the following init routines do then only need to add to f.
!  wd: also in the case where we have read in an existing snapshot??
!
        if (lroot) print* !(empty line)
        do i=1,init_loops
          if (lroot .and. init_loops/=1) &
              print'(A33,i3,A25)', 'start: -- performing loop number', i, &
              ' of initial conditions --'
          call init_gg        (f,xx,yy,zz)
          call init_uu        (f,xx,yy,zz)
          call init_lnrho     (f,xx,yy,zz)
          call init_ss        (f,xx,yy,zz)
          call init_aa        (f,xx,yy,zz)
          call init_rad       (f,xx,yy,zz)
          call init_lncc      (f,xx,yy,zz)
          call init_chiral    (f,xx,yy,zz)
          call init_uud       (f)
          call init_nd        (f)
          call init_ecr       (f,xx,yy,zz)
          call init_fcr       (f,xx,yy,zz)
          call init_special   (f,xx,yy,zz)
        enddo
!
!  check whether we want ionization
!
        if(leos_ionization) call ioninit(f)
        if(lradiation_ray) call radtransfer(f)
!
!  filter initial velocity
!  NOTE: this procedure is currently not very efficient,
!  because for all variables boundary conditions and communication
!  are done again and again for each variable.
!
        if(nfilter/=0) then
          do ifilter=1,nfilter
            call rmwig(f,df,iux,iuz,awig)
          enddo
          if(lroot) print*,'DONE: filter initial velocity, nfilter=',nfilter
        endif
!
!  Prepare particles.
!
        if (lparticles) then
          call particles_register_modules()
          call particles_rprint_list(.false.)
          call particles_initialize_modules(lstarting=.true.)
          call particles_init(f)
        endif
!
!  Set random seed independent of processor
!
        seed(1) = 1812
        call random_seed_wrapper(put=seed(1:nseed))
!
!  write to disk
!
        if (lwrite_ic) then
          call wsnap(trim(directory_snap)//'/VAR0',f, &
              mvar_io,ENUM=.false.,FLIST='varN.list')
          if (lparticles) &
              call particles_write_snapshot(trim(directory_snap)//'/PVAR0', &
              mvar_io,ENUM=.false.,FLIST='pvarN.list')
        endif
!
!  The option lnowrite writes everything except the actual var.dat file
!  This can be useful if auxiliary files are outdated, and don't want
!  to overwrite an existing var.dat
!
        inquire(FILE="NOERASE", EXIST=lnoerase)
        if (.not.lnowrite .and. .not.lnoerase) then
          if (ip<12) print*,'START: writing to ' // trim(directory_snap)//'/var.dat'
          call wsnap(trim(directory_snap)//'/var.dat',f,mvar_io,ENUM=.false.)
          if (lparticles) &
              call particles_write_snapshot(trim(directory_snap)//'/pvar.dat', &
              mvar_io,ENUM=.false.)
          call wtime(trim(directory)//'/time.dat',t)
        endif
        call wdim(trim(directory)//'/dim.dat')

!
!  also write full dimensions to data/ :
!
        if (lroot) then
          call wdim(trim(datadir)//'/dim.dat', &
            nxgrid+2*nghost,nygrid+2*nghost,nzgrid+2*nghost)
          if (lparticles) &
            call particles_write_pdim(trim(datadir)//'/pdim.dat')
        endif
!
!  write global variables:
!
        call wglobal()
!
!  Write input parameters to a parameter file (for run.x and IDL).
!  Do this late enough, so init_entropy etc. can adjust them
!
        call wparam()
!
!  Write information about pencils to disc
!
        call write_pencil_info()
!
!  Seed for random number generator to be used in forcing.f90. Have to
!  have the same on each  processor as forcing is applied in (global)
!  Beltrami modes.
!ajwm
!ajwm        seed(1) = 1812
!ajwm        call outpui(trim(directory)//'/seed.dat',seed,nseed)
!ajwm Commented as now handled bi Persist module


!
        call mpifinalize
        if (lroot) print*
        if (lroot) print*,'start.x has completed successfully'
        if (lroot) print* ! (finish with an empty line)
!
      endprogram
