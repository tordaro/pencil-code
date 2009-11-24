! $Id$
!
!  This module takes care of the continuity equation.
!
!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! CPARAM logical, parameter :: ldensity = .true.
! CPARAM logical, parameter :: ldensity_anelastic = .false.
!
! MVAR CONTRIBUTION 1
! MAUX CONTRIBUTION 0
!
! PENCILS PROVIDED lnrho; rho; rho1; glnrho(3); grho(3); uglnrho; ugrho
! PENCILS PROVIDED glnrho2; del2lnrho; del2rho; del6lnrho; del6rho
! PENCILS PROVIDED hlnrho(3,3); sglnrho(3); uij5glnrho(3)
!
!***************************************************************
module Density
!
  use Cparam
  use Cdata
  use Messages
  use EquationOfState
  use Sub, only : keep_compiler_quiet
!
  use Special
!
  implicit none
!
  include 'density.h'
!
  real, dimension (ninit) :: ampllnrho=0.0, widthlnrho=0.1
  real, dimension (ninit) :: rho_left=1.0, rho_right=1.0
  real, dimension (ninit) :: amplrho=0.0, phase_lnrho=0.0, radius_lnrho=0.5
  real, dimension (ninit) :: kx_lnrho=1.0, ky_lnrho=1.0, kz_lnrho=1.0
  real, dimension (ninit) :: kxx_lnrho=0.0, kyy_lnrho=0.0, kzz_lnrho=0.0
  real :: lnrho_const=0.0, rho_const=1.0
  real :: cdiffrho=0.0, diffrho=0.0, diffrho_hyper3=0.0, diffrho_shock=0.0
  real :: eps_planet=0.5, q_ell=5.0, hh0=0.0
  real :: xblob=0., yblob=0., zblob=0.
  real :: co1_ss=0.,co2_ss=0.,Sigma1=150.
  real :: lnrho_int=0.,lnrho_ext=0.,damplnrho_int=0.,damplnrho_ext=0.
  real :: wdamp=0.,density_floor=-1.0
  real :: mass_source_Mdot=0.,mass_source_sigma=0.
  real :: radial_percent_smooth=10.,rshift=0.0
  real, dimension (3) :: diffrho_hyper3_aniso=0.
  real, dimension (mz) :: lnrho_init_z=0.0,del2lnrho_init_z=0.0
  real, dimension (mz) :: dlnrhodz_init_z=0.0, glnrho2_init_z=0.0
  real, target :: plaw=0.0
  real :: lnrho_z_shift=0.0

  real, dimension (nz,3) :: glnrhomz

  real :: powerlr=3.0, zoverh=1.5, hoverr=0.05

  integer, parameter :: ndiff_max=4
  logical :: lmass_source=.false.,lcontinuity_gas=.true.
  logical :: lupw_lnrho=.false.,lupw_rho=.false.
  logical :: ldiff_normal=.false.,ldiff_hyper3=.false.,ldiff_shock=.false.
  logical :: ldiff_hyper3lnrho=.false.,ldiff_hyper3_aniso=.false.
  logical :: ldiff_hyper3_polar=.false.,lanti_shockdiffusion=.false.
  logical :: lfreeze_lnrhoint=.false.,lfreeze_lnrhoext=.false.
  logical :: lfreeze_lnrhosqu=.false.,lexponential_smooth=.false.
  logical :: lrho_as_aux=.false., ldiffusion_nolog=.false.
  logical :: lshare_plaw=.false.,lmassdiff_fix=.false.
  logical :: lcheck_negative_density=.false.
  logical :: lcalc_glnrhomean=.false.
!
  character (len=labellen), dimension(ninit) :: initlnrho='nothing'
  character (len=labellen) :: strati_type='lnrho_ss'
  character (len=labellen), dimension(ndiff_max) :: idiff=''
  character (len=labellen) :: borderlnrho='nothing'
  character (len=labellen) :: mass_source_profile='cylindric'
  character (len=5) :: iinit_str
  complex :: coeflnrho=0.
!
  integer :: iglobal_gg=0
!
  namelist /density_init_pars/ &
      ampllnrho,initlnrho,widthlnrho,                    &
      rho_left,rho_right,lnrho_const,rho_const,cs2bot,cs2top,       &
      radius_lnrho,eps_planet,xblob,yblob,zblob,                    &
      b_ell,q_ell,hh0,rbound,lwrite_stratification,                 &
      mpoly,strati_type,beta_glnrho_global,radial_percent_smooth,   &
      kx_lnrho,ky_lnrho,kz_lnrho,amplrho,phase_lnrho,coeflnrho,     &
      kxx_lnrho, kyy_lnrho, kzz_lnrho,                              &
      co1_ss,co2_ss,Sigma1,idiff,ldensity_nolog,lexponential_smooth,&
      wdamp,plaw,lcontinuity_gas,density_floor,lanti_shockdiffusion,&
      rshift,lrho_as_aux,ldiffusion_nolog,lnrho_z_shift,            &
      lshare_plaw, powerlr, zoverh, hoverr
!
  namelist /density_run_pars/ &
      cdiffrho,diffrho,diffrho_hyper3,diffrho_shock,                &
      cs2bot,cs2top,lupw_lnrho,lupw_rho,idiff,lmass_source,         &
      mass_source_profile, mass_source_Mdot, mass_source_sigma,     &
      lnrho_int,lnrho_ext,damplnrho_int,damplnrho_ext,              &
      wdamp,lfreeze_lnrhoint,lfreeze_lnrhoext,                      &
      lnrho_const,plaw,lcontinuity_gas,borderlnrho,                 &
      diffrho_hyper3_aniso,lfreeze_lnrhosqu,density_floor,          &
      lanti_shockdiffusion,lrho_as_aux,ldiffusion_nolog,            &
      lcheck_negative_density,lmassdiff_fix,lcalc_glnrhomean

! diagnostic variables (need to be consistent with reset list below)
  integer :: idiag_rhom=0       ! DIAG_DOC: $\left<\varrho\right>$
                                ! DIAG_DOC:   \quad(mean density)
  integer :: idiag_rho2m=0      ! DIAG_DOC:
  integer :: idiag_lnrho2m=0    ! DIAG_DOC:
  integer :: idiag_drho2m=0     ! DIAG_DOC:
  integer :: idiag_drhom=0      ! DIAG_DOC:
  integer :: idiag_rhomin=0     ! DIAG_DOC: $\min(\rho)$
  integer :: idiag_rhomax=0     ! DIAG_DOC: $\max(\rho)$
  integer :: idiag_ugrhom=0     ! DIAG_DOC: $\left<\uv\cdot\nabla\varrho\right>$
  integer :: idiag_uglnrhom=0   ! DIAG_DOC:
  integer :: idiag_lnrhomphi=0  ! PHIAVG_DOC: $\left<\ln\varrho\right>_\varphi$
  integer :: idiag_rhomphi=0    ! PHIAVG_DOC: $\left<\varrho\right>_\varphi$
  integer :: idiag_dtd=0        ! DIAG_DOC:
  integer :: idiag_rhomz=0      ! DIAG_DOC:
  integer :: idiag_rhomy=0      ! DIAG_DOC:
  integer :: idiag_rhomx=0      ! DIAG_DOC:
  integer :: idiag_rhomxy=0     ! DIAG_DOC:
  integer :: idiag_rhomxz=0     ! DIAG_DOC:
  integer :: idiag_rhomr=0      ! DIAG_DOC:
  integer :: idiag_totmass=0    ! DIAG_DOC: $\int\varrho\,dV$
  integer :: idiag_mass=0       ! DIAG_DOC: $\int\varrho\,dV$
!
  contains
!***********************************************************************
    subroutine register_density()
!
!  Initialise variables which should know that we solve the
!  compressible hydro equations: ilnrho; increase nvar accordingly.
!
!   4-jun-02/axel: adapted from hydro
!
      use Sub
      use FArrayManager
!
      call farray_register_pde('lnrho',ilnrho)
!
!  Identify version number (generated automatically by CVS).
!
      if (lroot) call svn_id( &
          "$Id$")
!
    endsubroutine register_density
!***********************************************************************
    subroutine initialize_density(f,lstarting)
!
!  Perform any post-parameter-read initialization i.e. calculate derived
!  parameters.
!
!  For compatibility with other applications, we keep the possibility
!  of giving diffrho units of dxmin*cs0, but cs0 is not well defined general
!
!  24-nov-02/tony: coded
!  31-aug-03/axel: normally, diffrho should be given in absolute units
!
      use BorderProfiles, only: request_border_driving
      use Deriv, only: der_pencil,der2_pencil
      use FArrayManager
      use Gravity, only: lnumerical_equilibrium
      use Mpicomm
      use SharedVariables
      use Sub, only: keep_compiler_quiet
!
      real, dimension (mx,my,mz,mfarray) :: f
      logical :: lstarting
!
      integer :: i,ierr
      logical :: lnothing
!
!  Set irho equal to ilnrho if we are considering non-logarithmic density.
!
      if (ldensity_nolog) irho=ilnrho
!
!  initialize cs2cool to cs20
!  (currently disabled, because it causes problems with mdarf auto-test)
!     cs2cool=cs20
!
!
      if (diffrho==0.) then
!
!  Made to work by adding diffrho + cdiffrho to the rprint reset list.
!
        diffrho=cdiffrho*dxmin*cs0
      endif
!
!  Turn off continuity equation term for 0-D runs.
!
      if (nxgrid*nygrid*nzgrid==1) then
        lcontinuity_gas=.false.
        print*, 'initialize_density: 0-D run, turned off continuity equation'
      endif
!
!  If fargo is used, continuity is taken care of in special/fargo.f90
!
      if (lfargo_advection) then 
        lcontinuity_gas=.false.
        print*,'initialize_density: fargo used. turned off continuity equation'
      endif
!
!  Initialize mass diffusion
!
      ldiff_normal=.false.
      ldiff_shock=.false.
      ldiff_hyper3=.false.
      ldiff_hyper3lnrho=.false.
      ldiff_hyper3_aniso=.false.
      ldiff_hyper3_polar=.false.
!
      lnothing=.false.
!
      do i=1,ndiff_max
        select case (idiff(i))
        case ('normal')
          if (lroot) print*,'diffusion: div(D*grad(rho))'
          ldiff_normal=.true.
        case ('hyper3')
          if (lroot) print*,'diffusion: (d^6/dx^6+d^6/dy^6+d^6/dz^6)rho'
          ldiff_hyper3=.true.
        case ('hyper3lnrho')
          if (lroot) print*,'diffusion: (d^6/dx^6+d^6/dy^6+d^6/dz^6)lnrho'
          ldiff_hyper3lnrho=.true.
       case ('hyper3_aniso','hyper3-aniso')
          if (lroot) print*,'diffusion: (Dx*d^6/dx^6 + Dy*d^6/dy^6 + Dz*d^6/dz^6)rho'
          ldiff_hyper3_aniso=.true.
        case ('hyper3_cyl','hyper3-cyl','hyper3_sph','hyper3-sph')
          if (lroot) print*,'diffusion: Dhyper/pi^4 *(Delta(rho))^6/Deltaq^2'
          ldiff_hyper3_polar=.true.
        case ('shock','diff-shock','diffrho-shock')
          if (lroot) print*,'diffusion: shock diffusion'
          ldiff_shock=.true.
        case ('','none')
          if (lroot .and. (.not. lnothing)) print*,'diffusion: nothing'
        case default
          write(unit=errormsg,fmt=*) 'initialize_density: ', &
              'No such value for idiff(',i,'): ', trim(idiff(i))
          call fatal_error('initialize_density',errormsg)
        endselect
        lnothing=.true.
      enddo
!
!  If we're timestepping, die or warn if the the diffusion coefficient that
!  corresponds to the chosen diffusion type is not set.
!
      if (lrun) then
        if (ldiff_normal.and.diffrho==0.0) &
            call warning('initialize_density', &
            'Diffusion coefficient diffrho is zero!')
        if ( (ldiff_hyper3 .or. ldiff_hyper3lnrho) &
            .and. diffrho_hyper3==0.0) &
            call fatal_error('initialize_density', &
            'Diffusion coefficient diffrho_hyper3 is zero!')
        if ( (ldiff_hyper3_aniso) .and.  &
             ((diffrho_hyper3_aniso(1)==0. .and. nxgrid/=1 ).or. &
              (diffrho_hyper3_aniso(2)==0. .and. nygrid/=1 ).or. &
              (diffrho_hyper3_aniso(3)==0. .and. nzgrid/=1 )) ) &
            call fatal_error('initialize_density', &
            'A diffusion coefficient of diffrho_hyper3 is zero!')
        if (ldiff_shock .and. diffrho_shock==0.0) &
            call fatal_error('initialize_density', &
            'diffusion coefficient diffrho_shock is zero!')
      endif
!
      if (lfreeze_lnrhoint) lfreeze_varint(ilnrho)    = .true.
      if (lfreeze_lnrhoext) lfreeze_varext(ilnrho)    = .true.
      if (lfreeze_lnrhosqu) lfreeze_varsquare(ilnrho) = .true.
!
! Tell the equation of state that we're here and what f variable we use
!
      if (ldensity_nolog) then
        call select_eos_variable('rho',irho)
      else
        call select_eos_variable('lnrho',ilnrho)
      endif
!
! Do not allow inconsistency between rho0 (from eos) and rho_const 
! or lnrho0 and lnrho_const. 
!
      if (rho0.ne.rho_const) then
        if (lroot) then 
          print*,"WARNING!"
          print*,"inconsistency between the density constants from eos  "
          print*,"(rho0 or lnrho0) and the ones from the density module "
          print*,"(rho_const or lnrho_const). It may damage your        "
          print*,"simulation if you are using them in different places. "
          call warning("initialize_density","")
        endif
      endif
!
      if (lnumerical_equilibrium) then
         if (lroot) print*,'initializing global gravity in density'
         call farray_register_global('gg',iglobal_gg,vector=3)
      endif
!
!  For backward compatibility, set lshare_plaw=T if llocal_iso is used.
!
      if (llocal_iso) lshare_plaw=.true.
      if (lshare_plaw) then
        call put_shared_variable('plaw',plaw,ierr)
        if (ierr/=0) call stop_it("local_isothermal_density: "//&
             "there was a problem when sharing plaw")
      endif
!
!  Possible to read initial stratification from file.
!
      if (.not. lstarting .and. lwrite_stratification) then
        if (lroot) print*, 'initialize_density: reading original stratification from stratification.dat'
        open(19,file=trim(directory_snap)//'/stratification.dat')
          if (ldensity_nolog) then
            if (lroot) then
              print*, 'initialize_density: currently only possible to read'
              print*, '                    *logarithmic* stratification from file'
            endif
            call fatal_error('initialize_density','')
          else
            read(19,*) lnrho_init_z
          endif
        close(19)
!
!  Need to precalculate some terms for anti shock diffusion.
!
        if (lanti_shockdiffusion) then        
          call der_pencil(3,lnrho_init_z,dlnrhodz_init_z)
          call der2_pencil(3,lnrho_init_z,del2lnrho_init_z)
          glnrho2_init_z=dlnrhodz_init_z**2
        endif
      endif
!
!  Must write stratification to file to counteract the shock diffusion of the
!  mean stratification.
!
      if (lanti_shockdiffusion .and. .not. lwrite_stratification) then
        if (lroot) print*, 'initialize_density: must have lwrite_stratification for anti shock diffusion'
        call fatal_error('','')
      endif
!
!  Possible to store non log rho as auxiliary variable.
!
      if (lrho_as_aux) then
        if (ldensity_nolog) then
          if (lroot) print*, 'initialize_density: makes no sense to have '// &
              'lrho_as_aux=T if already evolving non log rho'
          call fatal_error('initialize_density','')
        else
          call farray_register_auxiliary('rho',irho,communicated=.true.)
        endif
      endif
!
!  For diffusion term with non-logarithmic density we need to save rho
!  as an auxiliary variable.
!
      if (ldiffusion_nolog .and. .not. lrho_as_aux) then
        if (lroot) then
          print*, 'initialize_density: must have lrho_as_aux=T '// &
              'for non-logarithmic diffusion'
          print*, '  (consider setting lrho_as_aux=T and'
          print*, '   !  MAUX CONTRIBUTION 1'
          print*, '   !  COMMUNICATED AUXILIARIES 1'
          print*, '   in cparam.local)'
        endif
        call fatal_error('initialize_density','')
      endif
!
!  Tell the BorderProfiles module if we intend to use border driving, so
!  that the module can request the right pencils.
!
      if (borderlnrho/='nothing') call request_border_driving()
!
      call keep_compiler_quiet(f)
!
    endsubroutine initialize_density
!***********************************************************************
    subroutine init_lnrho(f)
!
!  Initialise logarithmic or non-logarithmic density.
!
!   7-nov-01/wolf: coded
!  28-jun-02/axel: added isothermal
!  15-oct-03/dave: added spherical shell (kws)
!
      use General, only: chn,complex_phase
      use Gravity, only: zref,z1,z2,gravz,nu_epicycle,potential, &
                         lnumerical_equilibrium
      use Initcond
      use IO
      use Mpicomm
      use Selfgravity, only: rhs_poisson_const
      use Sub
      use InitialCondition, only: initial_condition_lnrho
      use SharedVariables, only: get_shared_variable
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: pot,prof
      real, dimension (ninit) :: lnrho_left,lnrho_right
      real :: lnrhoint,cs2int,pot0
      real :: pot_ext,lnrho_ext,cs2_ext,tmp1,k_j2
      real :: zbot,ztop,haut
      real, dimension (nx) :: r_mn,lnrho,TT,ss
      real, pointer :: gravx
      complex :: omega_jeans
      integer :: j, ierr
      logical :: lnothing
!
      intent(inout) :: f
!
!  Define bottom and top height.
!
      zbot=xyz0(3)
      ztop=xyz0(3)+Lxyz(3)
!
!  Set default values for sound speed at top and bottom.
!  These may be updated in one of the following initialization routines.
!
      cs2top=cs20; cs2bot=cs20
!
!  Different initializations of lnrho (called from start).
!
      lnrho0      = log(rho0)
      lnrho_left  = log(rho_left)
      lnrho_right = log(rho_right)
!
      lnothing=.true.
!
      do j=1,ninit
!
        if (initlnrho(j)=='nothing') cycle
!
        lnothing=.false.
!
        call chn(j,iinit_str)
!
        select case(initlnrho(j))
!
        case('zero', '0'); f(:,:,:,ilnrho)=0.
        case('const_lnrho'); f(:,:,:,ilnrho)=lnrho_const
        case('const_rho'); f(:,:,:,ilnrho)=log(rho_const)
        case('constant'); f(:,:,:,ilnrho)=log(rho_left(j))
        case('mode')
          call modes(ampllnrho(j),coeflnrho,f,ilnrho,kx_lnrho(j), &
              ky_lnrho(j),kz_lnrho(j))
        case('blob')
          call blob(ampllnrho(j),f,ilnrho,radius_lnrho(j),xblob,yblob,zblob)
        case('blob_hs')
          print*, 'init_lnrho: put a blob in hydrostatic equilibrium:'// &
          'radius_lnrho, ampllnrho, position=',radius_lnrho(j), &
          ampllnrho(j), xblob, yblob, zblob
          call blob(ampllnrho(j),f,ilnrho,radius_lnrho(j),xblob,yblob,zblob)
          call blob(-ampllnrho(j),f,iss,radius_lnrho(j),xblob,yblob,zblob)
        case('isothermal'); call isothermal_density(f)
        case('local-isothermal'); call local_isothermal_density(f)
        case('power-law'); call power_law_disk(f)
        case('galactic-disk'); call exponential_fall(f)
        case('stratification'); call stratification(f,strati_type)
        case('stratification-x'); call stratification_x(f,strati_type)
        case('polytropic_simple'); call polytropic_simple(f)
        case('hydrostatic-z', '1')
          print*, 'init_lnrho: use polytropic_simple instead!'
        case('xjump')
          call jump(f,ilnrho,lnrho_left(j),lnrho_right(j),widthlnrho(j),'x')
        case('yjump')
          call jump(f,ilnrho,lnrho_left(j),lnrho_right(j),widthlnrho(j),'y')
        case('zjump')
          call jump(f,ilnrho,lnrho_left(j),lnrho_right(j),widthlnrho(j),'z')
        case('soundwave-x')
          call soundwave(ampllnrho(j),f,ilnrho,kx=kx_lnrho(j))
        case('soundwave-y')
          call soundwave(ampllnrho(j),f,ilnrho,ky=ky_lnrho(j))
        case('soundwave-z')
          call soundwave(ampllnrho(j),f,ilnrho,kz=kz_lnrho(j))
        case('sinwave-phase')
          call sinwave_phase(f,ilnrho,ampllnrho(j),kx_lnrho(j), &
              ky_lnrho(j),kz_lnrho(j),phase_lnrho(j))
        case('sinwave-phase-nolog')
          do m=m1,m2; do n=n1,n2
            f(l1:l2,m,n,ilnrho) = f(l1:l2,m,n,ilnrho) + &
                alog(1+amplrho(j)*sin(kx_lnrho(j)*x(l1:l2)+ &
                ky_lnrho(j)*y(m)+kz_lnrho(j)*z(n)+phase_lnrho(j)))
          enddo; enddo
        case('coswave-phase')
          call coswave_phase(f,ilnrho,ampllnrho(j),kx_lnrho(j), &
              ky_lnrho(j),kz_lnrho(j),phase_lnrho(j))
        case('sinwave-x')
          call sinwave(ampllnrho(j),f,ilnrho,kx=kx_lnrho(j))
        case('sinwave-y')
          call sinwave(ampllnrho(j),f,ilnrho,ky=ky_lnrho(j))
        case('sinwave-z')
          call sinwave(ampllnrho(j),f,ilnrho,kz=kz_lnrho(j))
        case('coswave-x')
          call coswave(ampllnrho(j),f,ilnrho,kx=kx_lnrho(j))
        case('coswave-y')
          call coswave(ampllnrho(j),f,ilnrho,ky=ky_lnrho(j))
        case('coswave-z')
          call coswave(ampllnrho(j),f,ilnrho,kz=kz_lnrho(j))
        case('triquad')
          call triquad(ampllnrho(j),f,ilnrho,kx_lnrho(j), &
              ky_lnrho(j),kz_lnrho(j), kxx_lnrho(j), kyy_lnrho(j), &
              kzz_lnrho(j))
        case('isotdisk')
          call isotdisk(powerlr,f,ilnrho,zoverh, hoverr)
          f(1:mx,1:my,1:mz,iss)=-(gamma-1)/gamma*f(1:mx,1:my,1:mz,ilnrho)
!          call isotdisk(powerlr,f,iss,zoverh,hoverr, -(gamma-1)/gamma)
        case('sinx_siny_sinz')
          call sinx_siny_sinz(ampllnrho(j),f,ilnrho, &
              kx_lnrho(j),ky_lnrho(j),kz_lnrho(j))
        case('corona'); call corona_init(f)
        case('gaussian3d')
          call gaussian3d(ampllnrho(j),f,ilnrho,radius_lnrho(j)) 
        case('plaw_gauss_disk'); call power_law_gaussian_disk(f)
        case('gaussian-z')
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho) = f(l1:l2,m,n,ilnrho) - &
                z(n)**2/(2*radius_lnrho(j)**2)
          enddo; enddo
        case('gauss-z-offset')
          do n=n1,n2
             f(:,:,n,ilnrho) = f(:,:,n,ilnrho) + &
                alog(exp(f(:,:,n,ilnrho))+ &
                ampllnrho(j)*(exp(-(z(n)+lnrho_z_shift)**2/ &
                (2*radius_lnrho(j)**2))))
          enddo
        case('gaussian-noise')
          If (lnrho_left(j) /= 0.) f(:,:,:,ilnrho)=lnrho_left(j)
          call gaunoise(ampllnrho(j),f,ilnrho,ilnrho)
        case('gaussian-noise-x')
!
!  Noise, but just x-dependent.
!
          call gaunoise(ampllnrho(j),f,ilnrho,ilnrho)
          f(:,:,:,ilnrho)=spread(spread(f(:,4,4,ilnrho),2,my),3,mz) !(watch 1-D)
        case('rho-jump-z', '2')
!
!  Density jump (for shocks).
!
          if (lroot) print*, 'init_lnrho: density jump; rho_left,right=', &
              rho_left(j), rho_right(j)
          if (lroot) print*, 'init_lnrho: density jump; widthlnrho=', &
              widthlnrho(j)
          do n=n1,n2; do m=m1,m2
            prof=0.5*(1.0+tanh(z(n)/widthlnrho(j)))
            f(l1:l2,m,n,ilnrho)=log(rho_left(j))+log(rho_left(j)/rho_right(j))*prof
          enddo; enddo
!
!  A*tanh(y/d) profile
!
        case('tanhy')
          if (lroot) print*,'init_lnrho: tangential discontinuity'
          do m=m1,m2
            prof=ampllnrho(j)*tanh(y(m)/widthlnrho(j))
            do n=n1,n2
              f(l1:l2,m,n,ilnrho)=prof
            enddo
          enddo
        case ('hydrostatic-z-2', '3')
!
!  Hydrostatic density stratification for isentropic atmosphere.
!
          if (lgravz) then
            if (lroot) print*,'init_lnrho: vertical density stratification'
            do n=n1,n2; do m=m1,m2
              f(l1:l2,m,n,ilnrho) = -grads0*z(n) &
                                + 1./gamma_m1*log( 1 + gamma_m1*gravz/grads0/cs20 &
                                              *(1-exp(-grads0*z(n))) )
            enddo; enddo
          endif
        case ('hydrostatic-r')
!
!  Hydrostatic radial density stratification for isentropic (or
!  isothermal) sphere.
!
          if (lgravr) then
            if (lroot) print*, &
                 'init_lnrho: radial density stratification (assumes s=const)'
!
            do n=n1,n2; do m=m1,m2
              r_mn=sqrt(x(l1:l2)**2+y(m)**2+z(n)**2)
              call potential(RMN=r_mn,POT=pot)
              call potential(R=r_ref,POT=pot0)
!  MEMOPT/AJ: commented out, since we do not use global potential anymore.
!            call output(trim(directory)//'/pot.dat',pot,1)
!
!  rho0, cs0, pot0 are the values at r=r_ref
!
              if (gamma/=1.0) then  ! isentropic
                f(l1:l2,m,n,ilnrho) = lnrho0 &
                                  + log(1 - gamma_m1*(pot-pot0)/cs20) / gamma_m1
              else                  ! isothermal
                f(l1:l2,m,n,ilnrho) = lnrho0 - (pot-pot0)/cs20
              endif
            enddo; enddo
!
!  The following sets gravity gg in order to achieve numerical
!  exact equilibrium at t=0.
!
            if (lnumerical_equilibrium) call numerical_equilibrium(f)
          endif
        case ('sph_isoth')
          if (lgravr) then
            if (lroot) print*, 'init_lnrho: isothermal sphere'
            haut=cs20/gamma
            TT=spread(cs20/gamma_m1,1,nx)
            do n=n1,n2
            do m=m1,m2
              r_mn=sqrt(x(l1:l2)**2+y(m)**2+z(n)**2)
              f(l1:l2,m,n,ilnrho)=lnrho0-r_mn/haut
              lnrho=f(l1:l2,m,n,ilnrho)
              call eoscalc(ilnrho_TT,lnrho,TT,ss=ss)
              f(l1:l2,m,n,iss)=ss
            enddo
            enddo
          endif
        case ('cylind_isoth')
          call get_shared_variable('gravx', gravx, ierr)
          if (ierr/=0) call stop_it("init_lnrho: "//&
             "there was a problem when getting gravx")
          if (lroot) print*, 'init_lnrho: isothermal cylindrical ring with gravx=', gravx
          haut=-cs20/gamma/gravx
          TT=spread(cs20/gamma_m1,1,nx)
          do n=n1,n2
          do m=m1,m2
            lnrho=lnrho0-(x(l1:l2)-r_ext)/haut
            f(l1:l2,m,n,ilnrho)=lnrho
            call eoscalc(ilnrho_TT,lnrho,TT,ss=ss)
            f(l1:l2,m,n,iss)=ss
          enddo
          enddo
        case ('isentropic-star')
!
!  Isentropic/isothermal hydrostatic sphere"
!    ss  = 0       for r<R,
!    cs2 = const   for r>R
!
!  Only makes sense if both initlnrho=initss='isentropic-star'
!
          if (lgravr) then
            if (lroot) print*, &
                 'init_lnrho: isentropic star with isothermal atmosphere'
            do n=n1,n2; do m=m1,m2
              r_mn=sqrt(x(l1:l2)**2+y(m)**2+z(n)**2)
              call potential(POT=pot,POT0=pot0,RMN=r_mn) ! gravity potential
!  MEMOPT/AJ: commented out, since we do not use global potential anymore.
!              call output(trim(directory)//'/pot.dat',pot,1)
!
!  rho0, cs0, pot0 are the values in the centre
!
              if (gamma /= 1) then
!  Note:
!  (a) `where' is expensive, but this is only done at
!      initialization.
!  (b) Comparing pot with pot_ext instead of r with r_ext will
!      only work if grav_r<=0 everywhere -- but that seems
!      reasonable.
                call potential(R=r_ext,POT=pot_ext) ! get pot_ext=pot(r_ext)
!  Do consistency check before taking the log() of a potentially
!  negative number
                tmp1 = 1 - gamma_m1*(pot_ext-pot0)/cs20
                if (tmp1 <= 0.) then
                  if (lroot) then
                    print*, 'BAD IDEA: Trying to calculate log(', tmp1, ')'
                    print*, '  for r_ext -- need to increase cs20?'
                  endif
                  call error('init_lnrho', 'Imaginary density values')
                endif
                lnrho_ext = lnrho0 + log(tmp1) / gamma_m1
                cs2_ext   = cs20*tmp1
!  Adjust for given cs2cool (if given) or set cs2cool (otherwise)
                if (cs2cool/=0) then
                  lnrho_ext = lnrho_ext - log(cs2cool/cs2_ext)
                else
                  cs2cool   = cs2_ext
                endif
!
!  Add temperature and entropy jump (such that pressure
!  remains continuous) if cs2cool was specified in start.in:
!
                where (pot <= pot_ext) ! isentropic for r<r_ext
                  f(l1:l2,m,n,ilnrho) = lnrho0 &
                                    + log(1 - gamma_m1*(pot-pot0)/cs20) / gamma_m1
                elsewhere           ! isothermal for r>r_ext
                  f(l1:l2,m,n,ilnrho) = lnrho_ext - gamma*(pot-pot_ext)/cs2cool
                endwhere
              else                  ! gamma=1 --> simply isothermal (I guess [wd])
                f(l1:l2,m,n,ilnrho) = lnrho0 - (pot-pot0)/cs20
              endif
            enddo; enddo
          endif

        case ('piecew-poly', '4')
!
!  Piecewise polytropic for stellar convection models.
!
          if (lroot) print*, &
             'init_lnrho: piecewise polytropic vertical stratification (lnrho)'
!  Top region.
          cs2int = cs0**2
          lnrhoint = lnrho0
          f(:,:,:,ilnrho) = lnrho0 ! just in case
          call polytropic_lnrho_z(f,mpoly2,zref,z2,ztop+Lz, &
                                  isothtop,cs2int,lnrhoint)
!  Unstable layer.
          call polytropic_lnrho_z(f,mpoly0,z2,z1,z2,0,cs2int,lnrhoint)
!  Stable layer.
          call polytropic_lnrho_z(f,mpoly1,z1,z0,z1,0,cs2int,lnrhoint)
!
!  Calculate cs2bot and cs2top for run.x (boundary conditions).
!
          cs2bot = cs2int + gamma/gamma_m1*gravz/(mpoly2+1)*(zbot-z0  )
          if (isothtop /= 0) then
            cs2top = cs20
          else
            cs2top = cs20 + gamma/gamma_m1*gravz/(mpoly0+1)*(ztop-zref)
          endif
        case ('piecew-disc', '41')
!
!  Piecewise polytropic for accretion discs.
!
          if (lroot) print*, &
               'init_lnrho: piecewise polytropic disc stratification (lnrho)'
!  Bottom region.
          cs2int = cs0**2
          lnrhoint = lnrho0
          f(:,:,:,ilnrho) = lnrho0 ! just in case
          call polytropic_lnrho_disc(f,mpoly1,zref,z1,z1, &
                                     0,cs2int,lnrhoint)
!  Unstable layer.
          call polytropic_lnrho_disc(f,mpoly0,z1,z2,z2,0,cs2int,lnrhoint)
!  Stable layer (top).
          call polytropic_lnrho_disc(f,mpoly2,z2,ztop,ztop, &
                                     isothtop,cs2int,lnrhoint)
!
!  Calculate cs2bot and cs2top for run.x (boundary conditions).
!
!  cs2bot = cs2int + gamma/gamma_m1*gravz*nu_epicycle**2/(mpoly2+1)* &
!         (zbot**2-z0**2)/2.
          cs2bot = cs20
          if (isothtop /= 0) then
            cs2top = cs20
          else
            cs2top = cs20 + gamma/gamma_m1*gravz*nu_epicycle**2/(mpoly0+1)* &
                    (ztop**2-zref**2)/2.
          endif
        case ('polytropic', '5')
!
!  Polytropic stratification.
!  cs0, rho0 and ss0=0 refer to height z=zref
!
          if (lroot) print*, &
                    'init_lnrho: polytropic vertical stratification (lnrho)'
!
          cs2int = cs20
          lnrhoint = lnrho0
          f(:,:,:,ilnrho) = lnrho0 ! just in case
!  Only one layer.
          call polytropic_lnrho_z(f,mpoly0,zref,z0,z0+2*Lz, &
               0,cs2int,lnrhoint)
!
!  Calculate cs2bot and cs2top for run.x (boundary conditions).
!
          cs2bot = cs20 + gamma*gravz/(mpoly0+1)*(zbot-zref)
          cs2top = cs20 + gamma*gravz/(mpoly0+1)*(ztop-zref)
        case('sound-wave', '11')
!
!  Sound wave (should be consistent with hydro module).
!
          if (lroot) print*,'init_lnrho: x-wave in lnrho; ampllnrho=', &
              ampllnrho(j)
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho)=lnrho_const+ampllnrho(j)*sin(kx_lnrho(j)*x(l1:l2))
          enddo; enddo
        case('sound-wave-exp')
!
!  Sound wave (should be consistent with hydro module).
!
          if (lroot) print*,'init_lnrho: x-wave in rho; ampllnrho=', &
              ampllnrho(j)
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho)=log(rho_const+amplrho(j)*sin(kx_lnrho(j)*x(l1:l2)))
          enddo; enddo
        case('sound-wave2')
!
!  Sound wave (should be consistent with hydro module).
!
          if (lroot) print*,'init_lnrho: x-wave in lnrho; ampllnrho=', &
              ampllnrho(j)
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho)=lnrho_const+ampllnrho(j)*cos(kx_lnrho(j)*x(l1:l2))
          enddo; enddo
        case('shock-tube', '13')
!
!  Shock tube test (should be consistent with hydro module).
!
          call information('init_lnrho','polytopic standing shock')
          do n=n1,n2; do m=m1,m2
            prof=0.5*(1.+tanh(x(l1:l2)/widthlnrho(j)))
            f(l1:l2,m,n,ilnrho)=log(rho_left(j))+ &
                (log(rho_right(j))-log(rho_left(j)))*prof
          enddo; enddo
        case('sin-xy')
!
!  sin profile in x and y.
!
          call information('init_lnrho','lnrho=sin(x)*sin(y)')
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho)=log(rho0) + &
                ampllnrho(j)*sin(kx_lnrho(j)*x(l1:l2))*sin(ky_lnrho(j)*y(m))
          enddo; enddo
        case('sin-xy-rho')
!
!  sin profile in x and y, but in rho, not ln(rho).
!
          call information('init_lnrho','rho=sin(x)*sin(y)')
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho)=log(rho0*(1+ &
                ampllnrho(j)*sin(kx_lnrho(j)*x(l1:l2))*sin(ky_lnrho(j)*y(m))))
          enddo; enddo
        case('linear')
!
!  Linear profile in kk.xxx.
!
          call information('init_lnrho','linear profile')
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho) = log(rho0) + &
                ampllnrho(j)*(kx_lnrho(j)*x(l1:l2)+ &
                ky_lnrho(j)*y(m)+kz_lnrho(j)*z(n))/ &
                sqrt(kx_lnrho(j)**2+ky_lnrho(j)**2+kz_lnrho(j)**2)
          enddo; enddo
        case('planet')
!
!  Planet solution of Goodman, Narayan & Goldreich (1987).
!  (Simple 3-D)
!
          call planet(rbound,f,eps_planet,radius_lnrho(j), &
              gamma,cs20,rho0,widthlnrho(j),hh0)
        case('planet_hc')
!
!  Planet solution of Goodman, Narayan & Goldreich (1987).
!  (3-D with hot corona)
!
          call planet_hc(amplrho(j),f,eps_planet, &
              radius_lnrho(j), gamma,cs20,rho0,widthlnrho(j))
        case('Ferriere')
          call information('init_lnrho','Ferriere set in entropy')
        case('Galactic-hs')
          call information('init_lnrho', &
              'Galactic hydrostatic equilibrium setup done in entropy')
        case('geo-kws')
!
!  Radial hydrostatic profile in shell region only.
!
          call information('init_lnrho', &
              'kws hydrostatic in spherical shell region')
          call shell_lnrho(f)
        case('geo-kws-constant-T','geo-benchmark')
!
!  Radial hydrostatic profile throughout box, which is consistent
!  with constant temperature in exterior regions, and gives continuous
!  density at shell boundaries.
!
          call information('init_lnrho', &
              'kws hydrostatic in spherical shell and exterior')
          call shell_lnrho(f)
        case ('step_xz')
          call fatal_error('init_lnrho','neutron_star initial condition '// &
              'is now in the special/neutron_star.f90 code')
        case('jeans-wave-x')
!
!  Soundwave + self gravity.
!
          omega_jeans = sqrt(cmplx(cs20*kx_lnrho(j)**2 - &
              rhs_poisson_const*rho0,0.))/(rho0*kx_lnrho(j))
          if (lroot) &
              print*,'Re(omega_jeans), Im(omega_jeans), Abs(omega_jeans)',&
              real(omega_jeans),aimag(omega_jeans),abs(omega_jeans)
!
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho) = lnrho_const + &
                ampllnrho(j)*sin(kx_lnrho(j)*x(l1:l2)+phase_lnrho(j))
            if (abs(omega_jeans)/=0.0) then
              f(l1:l2,m,n,iux) = f(l1:l2,m,n,iux) + &
                 abs(omega_jeans*ampllnrho(j)) * &
                 sin(kx_lnrho(j)*x(l1:l2)+phase_lnrho(j)+ &
                 complex_phase(omega_jeans*ampllnrho(j)))
            else
              f(l1:l2,m,n,iux) = f(l1:l2,m,n,iux) + 0.0
            endif
          enddo; enddo
        case('jeans-wave-oblique')
!
!  Soundwave + self gravity.
!
          k_j2 = kx_lnrho(j)**2 + ky_lnrho(j)**2 + kz_lnrho(j)**2
          omega_jeans = sqrt(cmplx(cs20*k_j2 - rhs_poisson_const*rho0,0.))/ &
              (rho0*sqrt(k_j2))
          print*,'Re(omega_jeans), Im(omega_jeans), Abs(omega_jeans)',&
              real(omega_jeans),aimag(omega_jeans),abs(omega_jeans)
! 
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho) = lnrho_const + &
              ampllnrho(j)*sin(kx_lnrho(j)*x(l1:l2) + &
              ky_lnrho(j)*y(m) + kz_lnrho(j)*z(n))
            if (kx_lnrho(j)/=0) &
                f(l1:l2,m,n,iux) = f(l1:l2,m,n,iux) + &
                abs(omega_jeans*ampllnrho(j)) * &
                sin(kx_lnrho(j)*x(l1:l2)+complex_phase(omega_jeans*ampllnrho(j)))
            if (ky_lnrho(j)/=0) &
                f(l1:l2,m,n,iuy) = f(l1:l2,m,n,iuy) + &
                abs(omega_jeans*ampllnrho(j)) * &
                sin(ky_lnrho(j)*y(m)+complex_phase(omega_jeans*ampllnrho(j)))
            if (kz_lnrho(j)/=0) &
                f(l1:l2,m,n,iuz) = f(l1:l2,m,n,iuz) + &
                abs(omega_jeans*ampllnrho(j)) * &
                sin(kz_lnrho(j)*z(n)+complex_phase(omega_jeans*ampllnrho(j)))
          enddo; enddo
!
        case('toomre-wave-x')
!
!  Soundwave + self gravity + (differential) rotation.
!
          omega_jeans = sqrt(cmplx(cs20*kx_lnrho(j)**2 + &
              Omega**2 - rhs_poisson_const*rho0,0.))/(rho0*kx_lnrho(j))
!
          print*,'Re(omega_jeans), Im(omega_jeans), Abs(omega_jeans)',&
              real(omega_jeans),aimag(omega_jeans),abs(omega_jeans)
!
          do n=n1,n2; do m=m1,m2
            f(l1:l2,m,n,ilnrho) = lnrho_const + &
              ampllnrho(j)*sin(kx_lnrho(j)*x(l1:l2))
            f(l1:l2,m,n,iux) = f(l1:l2,m,n,iux) + &
                abs(omega_jeans*ampllnrho(j)) * &
                sin(kx_lnrho(j)*x(l1:l2)+complex_phase(omega_jeans*ampllnrho(j)))
            f(l1:l2,m,n,iuy) = f(l1:l2,m,n,iuy) + &
                 abs(ampllnrho(j)* &
                 cmplx(0,-0.5*Omega/(kx_lnrho(j)*rho0))) * &
                 sin(kx_lnrho(j)*x(l1:l2)+complex_phase(ampllnrho(j)* &
                 cmplx(0,-0.5*Omega/(kx_lnrho(j)*rho0))))
          enddo; enddo
!
        case('compressive-shwave')
!  Should be consistent with density 
          f(:,:,:,ilnrho) = log(rho_const + f(:,:,:,ilnrho))
!
        case default
!
!  Catch unknown values
!
          write(unit=errormsg,fmt=*) 'No such value for initlnrho(' &
                            //trim(iinit_str)//'): ',trim(initlnrho(j))
          call fatal_error('init_lnrho',errormsg)
 
        endselect
!
        if (lroot) print*,'init_lnrho: initlnrho('//trim(iinit_str)//') = ', &
            trim(initlnrho(j))
!
      enddo  ! End loop over initial conditions.
!
!  Interface for user's own initial condition
!
      if (linitial_condition) call initial_condition_lnrho(f)
!
      if (lnothing.and.lroot) print*,'init_lnrho: nothing'
!
!  check that cs2bot,cs2top are ok
!  for runs with ionization or fixed ionization, don't print them
!
      if (leos_ionization .or. leos_fixed_ionization) then
        cs2top=impossible
        cs2bot=impossible
      else
        if (lroot) print*,'init_lnrho: cs2bot,cs2top=',cs2bot,cs2top
      endif
!
!  If unlogarithmic density considered, take exp of lnrho resulting from
!  initlnrho
!
      if (ldensity_nolog) f(:,:,:,irho)=exp(f(:,:,:,ilnrho))
!
!  sanity check
!
      if (notanumber(f(l1:l2,m1:m2,n1:n2,ilnrho))) then
        call error('init_lnrho', 'Imaginary density values')
      endif
!
    endsubroutine init_lnrho
!***********************************************************************
    subroutine calc_ldensity_pars(f)
!
!   31-aug-09/MR: adapted from calc_lhydro_pars
!
      use Sub, only: grad
      use Mpicomm, only: mpiallreduce_sum
!
      real, dimension (mx,my,mz,mfarray) :: f
      intent(in) :: f
!
      real :: fact
      real, dimension (nx,3) :: gradlnrho
      real, dimension (nz,3) :: temp
!
      integer :: j,nxy=nxgrid*nygrid
!
!  Calculate mean gradient of lnrho.
!
      if (lcalc_glnrhomean) then
        fact=1./nxy
        do n=1,nz
          glnrhomz(n,:)=0.
          do m=1,ny
            call grad(f,ilnrho,gradlnrho)
            do j=1,3
              glnrhomz(n,j)=glnrhomz(n,j)+sum(gradlnrho(:,j))
            enddo
          enddo
          if (nprocy>1) then             
            call mpiallreduce_sum(glnrhomz,temp,(/nz,3/),idir=2)
            glnrhomz = temp
          endif
          glnrhomz(n,:) = fact*glnrhomz(n,:)
        enddo
      endif
!
   endsubroutine calc_ldensity_pars
!***********************************************************************
    subroutine polytropic_lnrho_z( &
         f,mpoly,zint,zbot,zblend,isoth,cs2int,lnrhoint)
!
!  Implement a polytropic profile in ss above zbot. If this routine is
!  called several times (for a piecewise polytropic atmosphere), on needs
!  to call it from top to bottom.
!
!  zint    -- height of (previous) interface, where cs2int and lnrhoint
!             are set
!  zbot    -- z at bottom of layer
!  zblend  -- smoothly blend (with width whcond) previous ss (for z>zblend)
!             with new profile (for z<zblend)
!  isoth   -- flag for isothermal stratification;
!  lnrhoin -- value of lnrho at the interface, i.e. at the zint on entry,
!             at the zbot on exit
!  cs2int  -- same for cs2
!
      use Sub, only: step
      use Gravity, only: gravz
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mz) :: stp
      real :: tmp,mpoly,zint,zbot,zblend,beta1,cs2int,lnrhoint
      integer :: isoth
!
      intent(in)    :: mpoly,zint,zbot,zblend,isoth
      intent(out)   :: f
      intent(inout) :: cs2int,lnrhoint
!
      stp = step(z,zblend,widthlnrho(1))
      do n=n1,n2; do m=m1,m2
! NB: beta1 is not dT/dz, but dcs2/dz = (gamma-1)c_p dT/dz
        if (isoth/=0.0) then ! isothermal layer
          beta1 = 0.0
          tmp = gamma*gravz/cs2int*(z(n)-zint)
        else
          beta1 = gamma*gravz/(mpoly+1)
          tmp = 1.0 + beta1*(z(n)-zint)/cs2int
! Abort if args of log() are negative
          if ( (tmp<=0.0) .and. (z(n)<=zblend) ) then
            call fatal_error('polytropic_lnrho_z', &
                'Imaginary density values -- your z_inf is too low.')
          endif
          tmp = max(tmp,epsi)  ! ensure arg to log is positive
          tmp = lnrhoint + mpoly*log(tmp)
        endif
!
! smoothly blend the old value (above zblend) and the new one (below
! zblend) for the two regions:
!
        f(l1:l2,m,n,ilnrho) = stp(n)*f(l1:l2,m,n,ilnrho) + (1-stp(n))*tmp
!
      enddo; enddo
!
      if (isoth/=0.0) then
        lnrhoint = lnrhoint + gamma*gravz/cs2int*(zbot-zint)
      else
        lnrhoint = lnrhoint + mpoly*log(1 + beta1*(zbot-zint)/cs2int)
      endif
      cs2int = cs2int + beta1*(zbot-zint) ! cs2 at layer interface (bottom)
!
    endsubroutine polytropic_lnrho_z
!***********************************************************************
    subroutine polytropic_lnrho_disc( &
         f,mpoly,zint,zbot,zblend,isoth,cs2int,lnrhoint)
!
!  Implement a polytropic profile in a disc. If this routine is
!  called several times (for a piecewise polytropic atmosphere), on needs
!  to call it from bottom (middle of disc) upwards.
!
!  zint    -- height of (previous) interface, where cs2int and lnrhoint
!             are set
!  zbot    -- z at top of layer (name analogous with polytropic_lnrho_z)
!  zblend  -- smoothly blend (with width whcond) previous ss (for z>zblend)
!             with new profile (for z<zblend)
!  isoth   -- flag for isothermal stratification;
!  lnrhoint -- value of lnrho at the interface, i.e. at the zint on entry,
!             at the zbot on exit
!  cs2int  -- same for cs2
!
!  24-jun-03/ulf:  coded
!
      use Sub, only: step
      use Gravity, only: gravz, nu_epicycle
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mz) :: stp
      real :: tmp,mpoly,zint,zbot,zblend,beta1,cs2int,lnrhoint,nu_epicycle2
      integer :: isoth
!
      do n=n1,n2; do m=m1,m2
! NB: beta1 is not dT/dz, but dcs2/dz = (gamma-1)c_p dT/dz
        nu_epicycle2 = nu_epicycle**2
        if (isoth/=0.0) then ! isothermal layer
          beta1 = 0.0
          tmp = gamma*gravz*nu_epicycle2/cs2int*(z(n)**2-zint**2)/2.
        else
          beta1 = gamma*gravz*nu_epicycle2/(mpoly+1)
          tmp = 1.0 + beta1*(z(n)**2-zint**2)/cs2int/2.
! Abort if args of log() are negative
          if ( (tmp<=0.0) .and. (z(n)<=zblend) ) then
            call fatal_error('polytropic_lnrho_disc', &
                'Imaginary density values -- your z_inf is too low.')
          endif
          tmp = max(tmp,epsi)  ! ensure arg to log is positive
          tmp = lnrhoint + mpoly*log(tmp)
        endif
!
! smoothly blend the old value (above zblend) and the new one (below
! zblend) for the two regions:
!
        stp = step(z,zblend,widthlnrho(1))
        f(l1:l2,m,n,ilnrho) = stp(n)*f(l1:l2,m,n,ilnrho) + (1-stp(n))*tmp
!
      enddo; enddo
!
      if (isoth/=0.0) then
        lnrhoint = lnrhoint + gamma*gravz*nu_epicycle2/cs2int* &
                   (zbot**2-zint**2)/2.
      else
        lnrhoint = lnrhoint + mpoly*log(1 + beta1*(zbot**2-zint**2)/cs2int/2.)
      endif
      cs2int = cs2int + beta1*(zbot**2-zint**2)/2.
!
    endsubroutine polytropic_lnrho_disc
!***********************************************************************
    subroutine shell_lnrho(f)
!
!  Initialize density based on specified radial profile in
!  a spherical shell
!
!  22-oct-03/dave -- coded
!  21-aug-08/dhruba -- added spherical coordinates
!
      use Gravity, only: g0,potential
      use Mpicomm,only:stop_it
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
      real, dimension (nx) :: pot, r_mn
      real :: beta1,lnrho_int,lnrho_ext,pot_int,pot_ext
!
      beta1=g0/(mpoly+1)*gamma/gamma_m1  ! gamma_m1/gamma=R_{*} (for cp=1)
!
      if (lspherical_coords) then
!     densities at shell boundaries
        lnrho_int=lnrho0+mpoly*log(1+beta1*(x(l2)/x(l1)-1.))
        lnrho_ext=lnrho0
!
! always inside the fluid shell
        do imn=1,ny*nz
          n=nn(imn)
          m=mm(imn)
          f(l1:l2-1,m,n,ilnrho)=lnrho0+mpoly*log(1+beta1*(x(l2)/x(l1:l2-1)-1.))
          f(l2,m,n,ilnrho)=lnrho_ext
        enddo
!
      elseif (lcylindrical_coords) then
        call stop_it('shell_lnrho: this is not consistent with cylindrical coords')
      else
!     densities at shell boundaries
        lnrho_int=lnrho0+mpoly*log(1+beta1*(r_ext/r_int-1.))
        lnrho_ext=lnrho0
!
        do imn=1,ny*nz
          n=nn(imn)
          m=mm(imn)
!
          r_mn=sqrt(x(l1:l2)**2+y(m)**2+z(n)**2)
!
        ! in the fluid shell
          where (r_mn < r_ext .AND. r_mn > r_int) f(l1:l2,m,n,ilnrho)=lnrho0+mpoly*log(1+beta1*(r_ext/r_mn-1.))
        ! outside the fluid shell
            if (initlnrho(1)=='geo-kws') then
              where (r_mn >= r_ext) f(l1:l2,m,n,ilnrho)=lnrho_ext
              where (r_mn <= r_int) f(l1:l2,m,n,ilnrho)=lnrho_int
            elseif (initlnrho(1)=='geo-kws-constant-T'.or.initlnrho(1)=='geo-benchmark') then
              call potential(R=r_int,POT=pot_int)
              call potential(R=r_ext,POT=pot_ext)
              call potential(RMN=r_mn,POT=pot)
! gamma/gamma_m1=1/R_{*} (for cp=1)
              where (r_mn >= r_ext) f(l1:l2,m,n,ilnrho)=lnrho_ext+(pot_ext-pot)*exp(-lnrho_ext/mpoly)*gamma/gamma_m1
              where (r_mn <= r_int) f(l1:l2,m,n,ilnrho)=lnrho_int+(pot_int-pot)*exp(-lnrho_int/mpoly)*gamma/gamma_m1
            endif
        enddo
      endif
!
    endsubroutine shell_lnrho
!***********************************************************************
    subroutine numerical_equilibrium(f)
!
!  sets gravity gg in order to achieve an numerical exact equilbrium
!  at t=0. This is only valid for the polytropic case, i.e.
!
!    (1/rho) grad(P) = cs20 (rho/rho0)^(gamma-2) grad(rho)
!
      use Sub, only: grad
      use IO

      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: lnrho,cs2
      real, dimension (nx,3) :: glnrho
      real, dimension (nx,3) :: gg_mn
      integer :: j

      do m=m1,m2
      do n=n1,n2

        lnrho=f(l1:l2,m,n,ilnrho)
        cs2=cs20*exp(gamma_m1*(lnrho-lnrho0))
        call grad(f,ilnrho,glnrho)
        do j=1,3
          gg_mn(:,j)=cs2*glnrho(:,j)
        enddo
        f(l1:l2,m,n,iglobal_gg:iglobal_gg+2)=gg_mn

      enddo
      enddo

    endsubroutine numerical_equilibrium
!***********************************************************************
    subroutine pencil_criteria_density()
!
!  All pencils that the Density module depends on are specified here.
!
!  19-11-04/anders: coded
!
      if (ldensity_nolog) lpenc_requested(i_rho)=.true.
      if (lcontinuity_gas) then
        lpenc_requested(i_divu)=.true.
        if (ldensity_nolog) then
          lpenc_requested(i_ugrho)=.true.
        else
          lpenc_requested(i_uglnrho)=.true.
        endif
      endif
      if (ldiff_shock) then
        lpenc_requested(i_shock)=.true.
        lpenc_requested(i_gshock)=.true.
        if (ldensity_nolog .or. ldiffusion_nolog) then
          lpenc_requested(i_grho)=.true.
          lpenc_requested(i_del2rho)=.true.
          if (ldiffusion_nolog) lpenc_requested(i_rho1)=.true.
        else
          lpenc_requested(i_glnrho)=.true.
          lpenc_requested(i_glnrho2)=.true.
          lpenc_requested(i_del2lnrho)=.true.
        endif
      endif
      if (ldiff_normal) then
        if (ldensity_nolog .or. ldiffusion_nolog) then
          lpenc_requested(i_del2rho)=.true.
          if (ldiffusion_nolog) lpenc_requested(i_rho1)=.true.
        else
          lpenc_requested(i_glnrho2)=.true.
          lpenc_requested(i_del2lnrho)=.true.
        endif
      endif
      if (ldiff_hyper3) lpenc_requested(i_del6rho)=.true.
      if (ldiff_hyper3.and..not.ldensity_nolog) lpenc_requested(i_rho)=.true.
      if (ldiff_hyper3_polar.and..not.ldensity_nolog) &
           lpenc_requested(i_rho1)=.true.
      if (ldiff_hyper3lnrho) lpenc_requested(i_del6lnrho)=.true.
!
      if (lmass_source) then
        if (mass_source_profile=='bump') lpenc_requested(i_r_mn)=.true.
        if (mass_source_profile=='cylindric') lpenc_requested(i_rcyl_mn)=.true.
      endif
!
      if (lmassdiff_fix) lpenc_requested(i_rho1)=.true.
!
      lpenc_diagnos2d(i_lnrho)=.true.
      lpenc_diagnos2d(i_rho)=.true.
!
      if (idiag_rhom/=0 .or. idiag_rhomz/=0 .or. idiag_rhomy/=0 .or. &
           idiag_rhomx/=0 .or. idiag_rho2m/=0 .or. idiag_rhomin/=0 .or. &
           idiag_rhomax/=0 .or. idiag_rhomxy/=0 .or. idiag_rhomxz/=0 .or. &
           idiag_totmass/=0 .or. idiag_mass/=0 .or. idiag_drho2m/=0 .or. &
           idiag_drhom/=0) &
           lpenc_diagnos(i_rho)=.true.
      if (idiag_lnrho2m/=0) lpenc_diagnos(i_lnrho)=.true.
      if (idiag_ugrhom/=0) lpenc_diagnos(i_ugrho)=.true.
      if (idiag_uglnrhom/=0) lpenc_diagnos(i_uglnrho)=.true.
!
    endsubroutine pencil_criteria_density
!***********************************************************************
    subroutine pencil_interdep_density(lpencil_in)
!
!  Interdependency among pencils from the Density module is specified here.
!
!  19-11-04/anders: coded
!
      logical, dimension(npencils) :: lpencil_in
!
      if (ldensity_nolog) then
        if (lpencil_in(i_rho1)) lpencil_in(i_rho)=.true.
      else
        if (lpencil_in(i_rho)) lpencil_in(i_rho1)=.true.
      endif
      if (lpencil_in(i_uglnrho)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_glnrho)=.true.
      endif
      if (lpencil_in(i_ugrho)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_grho)=.true.
      endif
      if (lpencil_in(i_glnrho2)) lpencil_in(i_glnrho)=.true.
      if (lpencil_in(i_sglnrho)) then
        lpencil_in(i_sij)=.true.
        lpencil_in(i_glnrho)=.true.
      endif
      if (lpencil_in(i_uij5glnrho)) then
        lpencil_in(i_uij5)=.true.
        lpencil_in(i_glnrho)=.true.
      endif
!  The pencils glnrho and grho come in a bundle.
      if (lpencil_in(i_glnrho) .and. lpencil_in(i_grho)) then
        if (ldensity_nolog) then
          lpencil_in(i_grho)=.false.
        else
          lpencil_in(i_glnrho)=.false.
        endif
      endif
!
    endsubroutine pencil_interdep_density
!***********************************************************************
    subroutine calc_pencils_density(f,p)
!
!  Calculate Density pencils.
!  Most basic pencils should come first, as others may depend on them.
!
!  19-11-04/anders: coded
!
      use Sub, only: grad,dot,dot2,u_dot_grad,del2,del6,multmv,g2ij, dot_mn
      use Mpicomm, only: stop_it
!
      real, dimension (mx,my,mz,mfarray) :: f
      type (pencil_case) :: p
!
      integer :: i
!
      intent(inout) :: f,p
!
! lnrho
!
      if (lpencil(i_lnrho)) then
        if (ldensity_nolog) then
          p%lnrho=log(f(l1:l2,m,n,irho))
        else
          p%lnrho=f(l1:l2,m,n,ilnrho)
        endif
      endif
!
! rho1 and rho
!
      if (ldensity_nolog) then
        if (lpencil(i_rho)) then
          p%rho=f(l1:l2,m,n,irho)
          if (lcheck_negative_density .and. any(p%rho <= 0.)) &
            call fatal_error_local('calc_pencils_density', 'negative density detected')
        endif
        if (lpencil(i_rho1)) p%rho1=1.0/p%rho
      else
        if (lpencil(i_rho1)) p%rho1=exp(-f(l1:l2,m,n,ilnrho))
        if (lpencil(i_rho)) p%rho=1.0/p%rho1
      endif
!
! glnrho and grho
!
      if (lpencil(i_glnrho).or.lpencil(i_grho)) then
        if (ldensity_nolog) then
          call grad(f,ilnrho,p%grho)
          if (lpencil(i_glnrho)) then
            do i=1,3
              p%glnrho(:,i)=p%grho(:,i)/p%rho
            enddo
          endif
        else
          call grad(f,ilnrho,p%glnrho)
          if (lpencil(i_grho)) then
            if (irho/=0) then
              call grad(f,irho,p%grho)
            else
              do i=1,3
                p%grho(:,i)=p%rho*p%glnrho(:,i)
              enddo
            endif
          endif
        endif
      endif
!
! uglnrho
!
      if (lpencil(i_uglnrho)) then
        if (ldensity_nolog) then
          call dot(p%uu,p%glnrho,p%uglnrho)
        else
          if (lupw_rho) call stop_it("calc_pencils_density: you switched "//&
               "lupw_rho instead of lupw_lnrho")
          !!print*,'density: n,m, glnrho-x:', n,m, p%glnrho(:,1)
          !!print*,'density: n,m, glnrho-y:', n,m, p%glnrho(:,2)
          !!print*,'density: n,m, glnrho-z:', n,m, p%glnrho(:,3)
          !!print*,'density: n,m, uu-x:', n,m, p%uu(:,1)
          !!print*,'density: n,m, uu-y:', n,m, p%uu(:,2)
          !!print*,'density: n,m, uu-z:', n,m, p%uu(:,3)
          call u_dot_grad(f,ilnrho,p%glnrho,p%uu,p%uglnrho,UPWIND=lupw_lnrho)
          !!print*,'density: n,m, uglnrho-x:', n,m,p%uglnrho
          !!print*,'nl: n,m,density:', n,m,maxval(p%uglnrho), minval(p%uglnrho)
        endif
      endif
!
! ugrho
!
      if (lpencil(i_ugrho)) then
        if (ldensity_nolog) then
          if (lupw_lnrho) call stop_it("calc_pencils_density: you switched "//&
               "lupw_lnrho instead of lupw_rho")
          call u_dot_grad(f,ilnrho,p%grho,p%uu,p%ugrho,UPWIND=lupw_rho)
        else
          call dot(p%uu,p%grho,p%ugrho)
        endif
      endif
!
! glnrho2
!
      if (lpencil(i_glnrho2)) call dot2(p%glnrho,p%glnrho2)
!
! del2lnrho
!
      if (lpencil(i_del2lnrho)) then
        if (ldensity_nolog) then
          if (headtt) then
            call fatal_error('calc_pencils_density', &
                'del2lnrho not available for non-logarithmic mass density')
          endif
        else
          call del2(f,ilnrho,p%del2lnrho)
        endif
      endif
!
! del2rho
!
      if (lpencil(i_del2rho)) then
        if (ldensity_nolog) then
          call del2(f,ilnrho,p%del2rho)
        else
          if (irho/=0) then
            call del2(f,irho,p%del2rho)
          else
            if (headtt) &
                call fatal_error('calc_pencils_density',&
                'del2rho not available for logarithmic mass density')
          endif
        endif
      endif
!
! del6rho
!
      if (lpencil(i_del6rho)) then
        if (ldensity_nolog) then
          call del6(f,ilnrho,p%del6rho)
        else
          if (irho/=0) then
            call del6(f,irho,p%del6rho)
          else
            if (headtt) &
                call fatal_error('calc_pencils_density',&
                'del6rho not available for logarithmic mass density')
          endif
        endif
      endif
!
! del6lnrho
!
      if (lpencil(i_del6lnrho)) then
        if (ldensity_nolog) then
          if (headtt) then
            call fatal_error('calc_pencils_density', &
                             'del6lnrho not available for non-logarithmic mass density')
          endif
        else
          call del6(f,ilnrho,p%del6lnrho)
        endif
      endif
!
! hlnrho
!
      if (lpencil(i_hlnrho)) then
        if (ldensity_nolog) then
          if (headtt) then
            call fatal_error('calc_pencils_density', &
                             'hlnrho not available for non-logarithmic mass density')
          endif
        else
          call g2ij(f,ilnrho,p%hlnrho)
        endif
      endif
!
! sglnrho
!
      if (lpencil(i_sglnrho)) call multmv(p%sij,p%glnrho,p%sglnrho)
!
! uij5glnrho
!
      if (lpencil(i_uij5glnrho)) call multmv(p%uij5,p%glnrho,p%uij5glnrho)
!
    endsubroutine calc_pencils_density
!***********************************************************************
    subroutine calc_pencils_density_after_mn(f,p)
!
!  Do nothing, not even set stuff to zero 
!  But stuff needs to be added here. 
!  DM+PC
!  14-oct-09/dhruba: coded
!
      use EquationOfState, only: lnrho0, rho0
!
      real, dimension (mx,my,mz,mfarray) :: f
      type (pencil_case) :: p
!
      intent(in) :: f
      intent(inout) :: p

      call keep_compiler_quiet(f)
      call keep_compiler_quiet(p)
!
    endsubroutine calc_pencils_density_after_mn
!***********************************************************************
    subroutine density_before_boundary(f)
!
!  Actions to take before boundary conditions are set.
!
!   2-apr-08/anders: coded
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
!
      if ( (.not.ldensity_nolog) .and. (irho/=0) ) &
          f(l1:l2,m1:m2,n1:n2,irho)=exp(f(l1:l2,m1:m2,n1:n2,ilnrho))
!
    endsubroutine density_before_boundary
!***********************************************************************
    subroutine dlnrho_dt(f,df,p)
!
!  Continuity equation.
!  Calculate dlnrho/dt = - u.gradlnrho - divu
!
!   7-jun-02/axel: incoporated from subroutine pde
!
      use Deriv, only:der6
      use Diagnostics
      use Mpicomm, only: stop_it
      use Special, only: special_calc_density
      use Sub
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
!
      real, dimension (nx) :: fdiff, gshockglnrho, gshockgrho, tmp
      integer :: j
!
      intent(in)  :: f,p
      intent(out) :: df
!
!  Identify module and boundary conditions.
!
      if (headtt.or.ldebug) print*,'dlnrho_dt: SOLVE dlnrho_dt'
      if (headtt) call identify_bcs('lnrho',ilnrho)
!
!  Continuity equation.
!
      if (lcontinuity_gas) then
        if (ieos_profile=='nothing') then
          if (ldensity_nolog) then
            df(l1:l2,m,n,irho)   = df(l1:l2,m,n,irho)   - p%ugrho - p%rho*p%divu
          else
            df(l1:l2,m,n,ilnrho) = df(l1:l2,m,n,ilnrho) - p%uglnrho - p%divu
          endif
        else
          if (ldensity_nolog) then
            df(l1:l2,m,n,irho)   = df(l1:l2,m,n,irho)   &
              - profz_eos(n)*(p%ugrho + p%rho*p%divu)
          else
            df(l1:l2,m,n,ilnrho) = df(l1:l2,m,n,ilnrho) &
              - profz_eos(n)*(p%uglnrho + p%divu)
          endif
        endif
      endif
!
!  Mass sources and sinks.
!
      if (lmass_source) call mass_source(f,df,p)
!
!  Mass diffusion
!
      fdiff=0.0
!
      if (ldiff_normal) then  ! Normal diffusion operator
        if (ldensity_nolog) then
          fdiff = fdiff + diffrho*p%del2rho
        else
          if (ldiffusion_nolog) then
            fdiff = fdiff + p%rho1*diffrho*p%del2rho
          else
            fdiff = fdiff + diffrho*(p%del2lnrho+p%glnrho2)
          endif
        endif
        if (lfirst.and.ldt) diffus_diffrho=diffus_diffrho+diffrho
        if (headtt) print*,'dlnrho_dt: diffrho=', diffrho
      endif
!
!  Hyper diffusion
!
      if (ldiff_hyper3) then
        if (ldensity_nolog) then
          fdiff = fdiff + diffrho_hyper3*p%del6rho
        else
          if (ldiffusion_nolog) then
            fdiff = fdiff + p%rho1*diffrho_hyper3*p%del6rho
          else
            call fatal_error('dlnrho_dt','hyper diffusion not implemented for lnrho')
          endif
        endif
        if (lfirst.and.ldt) diffus_diffrho3=diffus_diffrho3+diffrho_hyper3
        if (headtt) print*,'dlnrho_dt: diffrho_hyper3=', diffrho_hyper3
      endif
!
      if (ldiff_hyper3_polar) then
        do j=1,3
          call der6(f,ilnrho,tmp,j,IGNOREDX=.true.)
          if (.not.ldensity_nolog) tmp=tmp*p%rho1
          fdiff = fdiff + diffrho_hyper3*pi4_1*tmp*dline_1(:,j)**2
        enddo
        if (lfirst.and.ldt) &
             diffus_diffrho3=diffus_diffrho3+diffrho_hyper3*pi4_1/dxyz_4
        if (headtt) print*,'dlnrho_dt: diffrho_hyper3=', diffrho_hyper3
      endif
!
      if (ldiff_hyper3_aniso) then
         if (ldensity_nolog) then
            call del6fj(f,diffrho_hyper3_aniso,ilnrho,tmp)
            fdiff = fdiff + tmp
!  Must divide by dxyz_6 here, because it is multiplied on later.
            if (lfirst.and.ldt) diffus_diffrho3=diffus_diffrho3+ &
                 (diffrho_hyper3_aniso(1)*dx_1(l1:l2)**6 + &
                  diffrho_hyper3_aniso(2)*dy_1(  m  )**6 + &
                  diffrho_hyper3_aniso(3)*dz_1(  n  )**6)/dxyz_6
            if (headtt) &
                 print*,'dlnrho_dt: diffrho_hyper3=(Dx,Dy,Dz)=',diffrho_hyper3_aniso
         else
            call stop_it("anisotropic hyperdiffusion not implemented for lnrho")
         endif
      endif
!
      if (ldiff_hyper3lnrho) then
        if (.not. ldensity_nolog) then
          fdiff = fdiff + diffrho_hyper3*p%del6lnrho
        endif
        if (lfirst.and.ldt) diffus_diffrho3=diffus_diffrho3+diffrho_hyper3
        if (headtt) print*,'dlnrho_dt: diffrho_hyper3=', diffrho_hyper3
      endif
!
!  Shock diffusion
!
      if (ldiff_shock) then
        if (ldensity_nolog) then
          call dot_mn(p%gshock,p%grho,gshockgrho)
          df(l1:l2,m,n,ilnrho) = df(l1:l2,m,n,ilnrho) + &
              diffrho_shock*p%shock*p%del2rho + diffrho_shock*gshockgrho
        else
          if (ldiffusion_nolog) then
            call dot_mn(p%gshock,p%grho,gshockgrho)
            df(l1:l2,m,n,ilnrho) = df(l1:l2,m,n,ilnrho) + p%rho1*( &
              diffrho_shock*p%shock*p%del2rho + diffrho_shock*gshockgrho )
          else
            call dot_mn(p%gshock,p%glnrho,gshockglnrho)
            df(l1:l2,m,n,ilnrho) = df(l1:l2,m,n,ilnrho) + &
                diffrho_shock*p%shock*(p%del2lnrho+p%glnrho2) + &
                diffrho_shock*gshockglnrho
!
!  Counteract the shock diffusion of the mean stratification. Must set
!  lwrite_stratification=T in start.in for this to work.
!            
            if (lanti_shockdiffusion) then
              df(l1:l2,m,n,ilnrho) = df(l1:l2,m,n,ilnrho) - diffrho_shock*( &
                  p%shock*(del2lnrho_init_z(n) + glnrho2_init_z(n) + &
                  2*(p%glnrho(:,3)-dlnrhodz_init_z(n))*dlnrhodz_init_z(n)) + &
                  p%gshock(:,3)*dlnrhodz_init_z(n) )
            endif
          endif
        endif
        if (lfirst.and.ldt) diffus_diffrho=diffus_diffrho+diffrho_shock*p%shock
        if (headtt) print*,'dlnrho_dt: diffrho_shock=', diffrho_shock
      endif
!
!  Interface for your personal subroutines calls
!
      if (lspecial) call special_calc_density(f,df,p)
!
!  Add diffusion term to continuity equation
!
      if (ldensity_nolog) then
        df(l1:l2,m,n,irho)   = df(l1:l2,m,n,irho)   + fdiff
      else
        df(l1:l2,m,n,ilnrho) = df(l1:l2,m,n,ilnrho) + fdiff
      endif
!
!  Improve energy and momentum conservation by compensating 
!  for mass diffusion
!
      if (lmassdiff_fix) then
        if (ldensity_nolog) then
          tmp = fdiff*p%rho1
        else
          tmp = fdiff
        endif
        if (lhydro) then
          df(l1:l2,m,n,iux) = df(l1:l2,m,n,iux) - p%uu(:,1)*tmp
          df(l1:l2,m,n,iuy) = df(l1:l2,m,n,iuy) - p%uu(:,2)*tmp
          df(l1:l2,m,n,iuz) = df(l1:l2,m,n,iuz) - p%uu(:,3)*tmp
        endif
        if (lentropy.and.(.not.pretend_lnTT)) then
          df(l1:l2,m,n,iss) = df(l1:l2,m,n,iss) - f(l1:l2,m,n,iss)*tmp
        elseif (lentropy.and.pretend_lnTT) then
          if (headtt) call warning('dlnrho_dt', &
              'massdiff_fix not yet implemented for pretend_lnTT')
        elseif (ltemperature.and.(.not. ltemperature_nolog)) then
          if (headtt) call warning('dlnrho_dt', &
              'massdiff_fix not yet implemented for ltemperature')
        elseif (ltemperature.and.ltemperature_nolog) then
          if (headtt) call warning('dlnrho_dt', &
              'massdiff_fix not yet implemented for ltemperature_nolog')
        endif
      endif
!
!  Multiply diffusion coefficient by Nyquist scale.
!
      if (lfirst.and.ldt) then
        diffus_diffrho =diffus_diffrho *dxyz_2
        diffus_diffrho3=diffus_diffrho3*dxyz_6
        if (headtt.or.ldebug) then
          print*,'dlnrho_dt: max(diffus_diffrho ) =', maxval(diffus_diffrho)
          print*,'dlnrho_dt: max(diffus_diffrho3) =', maxval(diffus_diffrho3)
        endif
      endif
!
!  Apply border profile
!
      if (lborder_profiles) call set_border_density(f,df,p)
!
!  2d-averages
!  Note that this does not necessarily happen with ldiagnos=.true.
!
      if (l2davgfirst) then
        if (idiag_lnrhomphi/=0) call phisum_mn_name_rz(p%lnrho,idiag_lnrhomphi)
        if (idiag_rhomphi/=0)   call phisum_mn_name_rz(p%rho,idiag_rhomphi)
        if (idiag_rhomxz/=0)    call ysum_mn_name_xz(p%rho,idiag_rhomxz)
        if (idiag_rhomxy/=0)    call zsum_mn_name_xy(p%rho,idiag_rhomxy)
      endif
!
!  1d-averages. Happens at every it1d timesteps, NOT at every it1
!
      if (l1ddiagnos) then
        if (idiag_rhomr/=0)    call phizsum_mn_name_r(p%rho,idiag_rhomr)
        if (idiag_rhomz/=0)    call xysum_mn_name_z(p%rho,idiag_rhomz)
        if (idiag_rhomx/=0)    call yzsum_mn_name_x(p%rho,idiag_rhomx)
        if (idiag_rhomy/=0)    call xzsum_mn_name_y(p%rho,idiag_rhomy)
      endif
!
!  Calculate density diagnostics
!
      if (ldiagnos) then
        if (idiag_rhom/=0)     call sum_mn_name(p%rho,idiag_rhom)
        if (idiag_totmass/=0)  call sum_mn_name(p%rho,idiag_totmass,lint=.true.)
        if (idiag_mass/=0)     call integrate_mn_name(p%rho,idiag_mass)
        if (idiag_rhomin/=0) &
            call max_mn_name(-p%rho,idiag_rhomin,lneg=.true.)
        if (idiag_rhomax/=0)   call max_mn_name(p%rho,idiag_rhomax)
        if (idiag_rho2m/=0)    call sum_mn_name(p%rho**2,idiag_rho2m)
        if (idiag_lnrho2m/=0)  call sum_mn_name(p%lnrho**2,idiag_lnrho2m)
        if (idiag_drho2m/=0)   call sum_mn_name((p%rho-rho0)**2,idiag_drho2m)
        if (idiag_drhom/=0)    call sum_mn_name(p%rho-rho0,idiag_drhom)
        if (idiag_ugrhom/=0)   call sum_mn_name(p%ugrho,idiag_ugrhom)
        if (idiag_uglnrhom/=0) call sum_mn_name(p%uglnrho,idiag_uglnrhom)
        if (idiag_dtd/=0) &
            call max_mn_name(diffus_diffrho/cdtv,idiag_dtd,l_dt=.true.)
      endif
!
    endsubroutine dlnrho_dt
!***********************************************************************
    subroutine set_border_density(f,df,p)
!
!  Calculates the driving term for the border profile
!  of the lnrho variable.
!
!  28-jul-06/wlad: coded
!
      use BorderProfiles,  only: border_driving,set_border_initcond
      use Mpicomm,         only: stop_it
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      real, dimension (nx) :: f_target
      type (pencil_case)  :: p
!
      select case(borderlnrho)
!
      case('zero','0')
        if (plaw.ne.0) call stop_it("borderlnrho: density is not flat but "//&
             "you are calling zero border")
        if (ldensity_nolog) then  
          f_target=0.
        else
          f_target=1.
        endif
!
      case('constant')
        if (plaw.ne.0) call stop_it("borderlnrho: density is not flat but "//&
             "you are calling constant border")
        if (ldensity_nolog) then 
          f_target=rho_const
        else
          f_target=lnrho_const
        endif
!
      case('initial-condition')
        call set_border_initcond(f,ilnrho,f_target)
!
      case('nothing')
        if (lroot.and.ip<=5) &
            print*,"set_border_lnrho: borderlnrho='nothing'"
!
      case default
        write(unit=errormsg,fmt=*) &
             'set_border_lnrho: No such value for borderlnrho: ', &
             trim(borderlnrho)
        call fatal_error('set_border_lnrho',errormsg)
      endselect
!
      if (borderlnrho/='nothing') then
        call border_driving(f,df,p,f_target,ilnrho)
      endif
!
    endsubroutine set_border_density
!***********************************************************************
!  Here comes a collection of different density stratification routines
!***********************************************************************
    subroutine isothermal_density(f)
!
!  Isothermal stratification (for lnrho and ss)
!  This routine should be independent of the gravity module used.
!  When entropy is present, this module also initializes entropy.
!
!  Sound speed (and hence Temperature), and density (at infinity) are
!  initialised to their respective reference values:
!           sound speed: cs^2_0            from start.in
!           density: rho0 = exp(lnrho0)
!
!   8-jul-02/axel: incorporated/adapted from init_lnrho
!  11-jul-02/axel: fixed sign; should be tmp=gamma*pot/cs20
!  02-apr-03/tony: made entropy explicit rather than using tmp/-gamma
!  11-jun-03/tony: moved entropy initialisation to separate routine
!                  to allow isothermal condition for arbitrary density
!
      use Gravity
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: pot,tmp
      real :: cp1
!
!  Stratification depends on the gravity potential
!
      if (lroot) print*,'isothermal_density: isothermal stratification'
      if (gamma/=1.0) then
        if ((.not. lentropy) .and. (.not. ltemperature)) & 
          call fatal_error('isothermal_density','for gamma/=1.0, you need entropy or temperature!');
      endif
!
      call get_cp1(cp1)
      do n=n1,n2
        do m=m1,m2
          call potential(x(l1:l2),y(m),z(n),pot=pot)
          tmp=-gamma*pot/cs20
          f(l1:l2,m,n,ilnrho) = f(l1:l2,m,n,ilnrho) + lnrho0 + tmp
          if (lentropy) f(l1:l2,m,n,iss) = f(l1:l2,m,n,iss) &
               -gamma_m1*(f(l1:l2,m,n,ilnrho)-lnrho0)/gamma
          if (ltemperature) f(l1:l2,m,n,ilnTT)=log(cs20*cp1/gamma_m1)
        enddo
      enddo
!
!  cs2 values at top and bottom may be needed to boundary conditions.
!  The values calculated here may be revised in the entropy module.
!
      cs2bot=cs20
      cs2top=cs20
!
    endsubroutine isothermal_density
!***********************************************************************
    subroutine local_isothermal_density(f)
!                                                                   
!  Stratification depends on the gravity potential, which in turn   
!  varies with radius. This reproduces the initial condition of the 
!  locally isothermal approximation in which temperature is a power 
!  law of radial distance
!
!  18-apr-07/wlad : coded
!
      use FArrayManager
      use Mpicomm,     only:stop_it 
      use Initcond,    only:set_thermodynamical_quantities
      use Gravity,     only:potential,acceleration
      use Sub,         only:get_radial_distance,grad,power_law
      use Selfgravity, only:calc_selfpotential
      use Boundcond,   only:update_ghosts
      use Particles_nbody, only:get_totalmass
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx)   :: strat,tmp1,tmp2,cs2
      real, dimension (mx)   :: rr_sph,rr,rr_cyl,lnrhomid
      real                   :: ptlaw,rmid,lat,g0
      integer, pointer       :: iglobal_cs2,iglobal_glnTT
      integer                :: ics2
      logical                :: lheader,lenergy,lpresent_zed
!
      if (lroot) print*,&
           'local isothermal_density: locally isothermal approximation'
      if (lroot) print*,'Radial stratification with power law=',plaw
!
      lenergy=ltemperature.or.lentropy
!
!  Set the sound speed
!
      call get_ptlaw(ptlaw)
      do m=1,my
        do n=1,mz
          lheader=((m==1).and.(n==1).and.lroot)
          call get_radial_distance(rr_sph,rr_cyl)
          if (lsphere_in_a_box.or.lspherical_coords) then 
            rr=rr_sph
          elseif (lcylinder_in_a_box.or.lcylindrical_coords) then
            rr=rr_cyl
          else
            call stop_it("local_isothermal_density: "//&
                "no valid coordinate system")
          endif
!
          call power_law(cs20,rr,ptlaw,cs2,r_ref)
!
!  Store cs2 in one of the free slots of the f-array
!
          if (llocal_iso) then 
            nullify(iglobal_cs2)
            call farray_use_global('cs2',iglobal_cs2)
            ics2=iglobal_cs2
          elseif (ltemperature) then 
            ics2=ilnTT
          elseif (lentropy) then 
            ics2=iss
          endif
          f(:,m,n,ics2)=cs2
        enddo
      enddo
!
!  Stratification is only coded for 3D runs. But as 
!  cylindrical and spherical coordinates store the 
!  vertical direction in different slots, one has to 
!  do this trick below to decide whether this run is 
!  2D or 3D. 
!
      lpresent_zed=.false.
      if (lspherical_coords) then 
        if (nygrid/=1) lpresent_zed=.true.
      else
        if (nzgrid/=1) lpresent_zed=.true.
      endif
!
!  Pencilize the density allocation.
!
      do n=1,mz
        do m=1,my
!
          lheader=lroot.and.(m==1).and.(n==1)
!
!  Midplane density
!
          call get_radial_distance(rr_sph,rr_cyl)
          if (lsphere_in_a_box.or.lspherical_coords) then 
            rr=rr_sph
          elseif (lcylinder_in_a_box.or.lcylindrical_coords) then
            rr=rr_cyl
          endif
!
          if (lexponential_smooth) then
            !radial_percent_smooth = percentage of the grid
            !that the smoothing is applied
            rmid=rshift+(xyz1(1)-xyz0(1))/radial_percent_smooth
            lnrhomid=log(rho0) &
                + plaw*log((1-exp( -((rr-rshift)/rmid)**2 ))/rr)
          else
            lnrhomid=log(rho0)-.5*plaw*log((rr/r_ref)**2+rsmooth**2)
          endif
!
!  Vertical stratification, if needed
!
          if (.not.lcylindrical_gravity.and.lpresent_zed) then 
            if (lheader) &
                 print*,"Adding vertical stratification with "//&
                 "scale height h/r=",cs0
!
!  Get the sound speed
!
            cs2=f(:,m,n,ics2)
!            
            if (lspherical_coords.or.lsphere_in_a_box) then
              ! uphi2/r = -gr + dp/dr
              if (lgrav) then
                call acceleration(tmp1)
              elseif (lparticles_nbody) then
                call get_totalmass(g0) ; tmp1=-g0/rr_sph**2
              else
                print*,"both gravity and particles_nbody are switched off"
                print*,"there is no gravity to determine the stratification"
                call stop_it("local_isothermal_density")
              endif
!                
              tmp2=-tmp1*rr_sph - cs2*(plaw + ptlaw)/gamma
              lat=pi/2-y(m)
              strat=(tmp2*gamma/cs2) * log(cos(lat))
            else
!
!  The subroutine "potential" yields the whole gradient.
!  I want the function that partially derived in
!  z gives g0/r^3 * z. This is NOT -g0/r
!  The second call takes care of normalizing it 
!  i.e., there should be no correction at midplane
!
              if (lgrav) then 
                call potential(POT=tmp1,RMN=rr_sph)
                call potential(POT=tmp2,RMN=rr_cyl)
              elseif (lparticles_nbody) then
                call get_totalmass(g0) 
                tmp1=-g0/rr_sph ; tmp2=-g0/rr_cyl
              else
                print*,"both gravity and particles_nbody are switched off"
                print*,"there is no gravity to determine the stratification"
                call stop_it("local_isothermal_density")
              endif
              strat=-(tmp1-tmp2)/cs2
              if (lenergy) strat=gamma*strat
            endif
!
          else
!  No stratification
            strat=0.
          endif
          f(:,m,n,ilnrho) = max(lnrhomid+strat,density_floor)
        enddo
      enddo
!
!  Correct the velocities by this pressure gradient
!
      call correct_pressure_gradient(f,ics2,ptlaw)
!
!  Correct the velocities for self-gravity
!
      call correct_for_selfgravity(f)
!
!  Set the thermodynamical variable
!
      if (llocal_iso) then
        call set_thermodynamical_quantities&
             (f,ptlaw,ics2,iglobal_cs2,iglobal_glnTT)
      else
        call set_thermodynamical_quantities(f,ptlaw,ics2)
      endif
!
    endsubroutine local_isothermal_density
!***********************************************************************
    subroutine correct_pressure_gradient(f,ics2,ptlaw)
! 
!  Correct for pressure gradient term in the centrifugal force.
!  For now, it only works for flat (isothermal) or power-law 
!  sound speed profiles, because the temperature gradient is 
!  constructed analytically.
!
!  21-aug-07/wlad : coded
!
      use FArrayManager
      use Mpicomm,only: stop_it
      use Sub,    only: get_radial_distance,grad
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx,3) :: glnrho
      real, dimension (nx)   :: rr,rr_cyl,rr_sph
      real, dimension (nx)   :: cs2,tmp1,tmp2,corr,gslnrho,gslnTT
      integer                :: i,ics2
      logical                :: lheader,lenergy
      real                   :: ptlaw
!
      if (lroot) print*,'Correcting density gradient on the '//&
           'centrifugal force'
!
      lenergy=ltemperature.or.lentropy
!
      do m=m1,m2
        do n=n1,n2
          lheader=((m==m1).and.(n==n1).and.lroot)
!
!  Get the density gradient
!
          call get_radial_distance(rr_sph,rr_cyl)
          call grad(f,ilnrho,glnrho)
          if (lcartesian_coords) then
            gslnrho=(glnrho(:,1)*x(l1:l2) + glnrho(:,2)*y(m))/rr_cyl
            !!gs= gx*cos + gy*sin
          else if (lcylindrical_coords) then 
            gslnrho=glnrho(:,1)
          else if (lspherical_coords) then 
            gslnrho=glnrho(:,1)
          endif
!
!  Get sound speed and calculate the temperature gradient
!
          cs2=f(l1:l2,m,n,ics2);rr=rr_cyl
          if (lspherical_coords.or.lsphere_in_a_box) rr=rr_sph
          gslnTT=-ptlaw/((rr/r_ref)**2+rsmooth**2)*rr/r_ref**2
!
!  Correct for cartesian or spherical
!
          corr=(gslnrho+gslnTT)*cs2
          if (lenergy) corr=corr/gamma
!
          if (lcartesian_coords) then
            tmp1=(f(l1:l2,m,n,iux)**2+f(l1:l2,m,n,iuy)**2)/rr_cyl**2
            tmp2=tmp1 + corr/rr_cyl
          elseif (lcylindrical_coords) then
            tmp1=(f(l1:l2,m,n,iuy)/rr_cyl)**2
            tmp2=tmp1 + corr/rr_cyl
          elseif (lspherical_coords) then
            tmp1=(f(l1:l2,m,n,iuz)/rr_sph)**2
            tmp2=tmp1 + corr/rr_sph
          endif
!
!  Make sure the correction does not impede centrifugal equilibrium
!
          do i=1,nx
            if (tmp2(i).lt.0.) then
              if (rr(i) .lt. r_int) then
                !it's inside the frozen zone, so 
                !just set tmp2 to zero and emit a warning
                tmp2(i)=0.
                if ((ip<=10).and.lheader) &
                     call warning('correct_density_gradient','Cannot '//&
                     'have centrifugal equilibrium in the inner '//&
                     'domain. The pressure gradient is too steep.')
              else
                print*,'correct_density_gradient: ',&
                       'cannot have centrifugal equilibrium in the inner ',&
                       'domain. The pressure gradient is too steep at ',&
                       'x,y,z=',x(i+nghost),y(m),z(n)
                print*,'the angular frequency here is',tmp2(i)
                call stop_it("")
              endif
            endif
          enddo
!
!  Correct the velocities
!
          if (lcartesian_coords) then
            f(l1:l2,m,n,iux)=-sqrt(tmp2)*y(  m  )
            f(l1:l2,m,n,iuy)= sqrt(tmp2)*x(l1:l2)
          elseif (lcylindrical_coords) then
            f(l1:l2,m,n,iuy)= sqrt(tmp2)*rr_cyl
          elseif (lspherical_coords) then 
            f(l1:l2,m,n,iuz)= sqrt(tmp2)*rr_sph
          endif
        enddo
      enddo
!
    endsubroutine correct_pressure_gradient
!***********************************************************************
    subroutine exponential_fall(f)
!
!  Exponentially falling radial density profile.
!
!  21-aug-07/wlad: coded 
!
      use Sub, only: get_radial_distance
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx) :: rr_sph,rr_cyl,arg
      real :: rmid,fac
      logical :: lheader
!
      if (lroot) print*,'setting exponential falling '//&
           'density with e-fold=',r_ref
!
      fac=pi/2
      do m=1,my
        do n=1,mz
          lheader=lroot.and.(m==1).and.(n==1)
          call get_radial_distance(rr_sph,rr_cyl)
          f(1:mx,m,n,ilnrho) = lnrho0 - rr_cyl/r_ref
          if (lexponential_smooth) then 
            rmid=rshift+(xyz1(1)-xyz0(1))/radial_percent_smooth
            arg=(rr_cyl-rshift)/rmid
            f(1:mx,m,n,ilnrho) = f(1:mx,m,n,ilnrho)*&
                 .5*(1+atan(arg)/fac)
          endif
        enddo
      enddo
!
!  Add self-gravity's contribution to the centrifugal force
!
      call correct_for_selfgravity(f)
!
    endsubroutine exponential_fall
!***********************************************************************
    subroutine correct_for_selfgravity(f)
!        
!  Correct for the fluid's self-gravity in the 
!  centrifugal force
!
!  03-dec-07/wlad: coded
!
      use Sub,         only:get_radial_distance,grad
      use Selfgravity, only:calc_selfpotential
      use Boundcond,   only:update_ghosts
      use Mpicomm,     only:stop_it
!
      real, dimension (mx,my,mz,mfarray) :: f

      real, dimension (nx,3) :: gpotself
      real, dimension (nx) :: tmp1,tmp2
      real, dimension (nx) :: gspotself,rr_cyl,rr_sph
      logical :: lheader
      integer :: i
!
!  Do nothing if self-gravity is not called
!
      if (lselfgravity) then
!
        if (lroot) print*,'Correcting for self-gravity on the '//&
             'centrifugal force'
!
!  feed linear density into the poisson solver
!
        f(:,:,:,ilnrho) = exp(f(:,:,:,ilnrho))
        call calc_selfpotential(f)
        f(:,:,:,ilnrho) = alog(f(:,:,:,ilnrho))
!
!  update the boundaries for the self-potential
!
        call update_ghosts(f)
!
        do n=n1,n2
          do m=m1,m2
!
            lheader=((m==m1).and.(n==n1).and.lroot)
!
!  Get the potential gradient
!
            call get_radial_distance(rr_sph,rr_cyl)
            call grad(f,ipotself,gpotself)
!
!  correct the angular frequency phidot^2
!
            if (lcartesian_coords) then 
              gspotself=(gpotself(:,1)*x(l1:l2) + gpotself(:,2)*y(m))/rr_cyl
              tmp1=(f(l1:l2,m,n,iux)**2+f(l1:l2,m,n,iuy)**2)/rr_cyl**2
              tmp2=tmp1+gspotself/rr_cyl
            elseif (lcylindrical_coords) then 
              gspotself=gpotself(:,1)
              tmp1=(f(l1:l2,m,n,iuy)/rr_cyl)**2
              tmp2=tmp1+gspotself/rr_cyl
            elseif (lspherical_coords) then
              gspotself=gpotself(:,1)*sinth(m) + gpotself(:,2)*costh(m)
              tmp1=(f(l1:l2,m,n,iuz)/(rr_sph*sinth(m)))**2
              tmp2=tmp1 + gspotself/(rr_sph*sinth(m)**2)
            endif
!
!  Catch negative values of phidot^2
!
            do i=1,nx
              if (tmp2(i).lt.0.) then
                if (rr_cyl(i) .lt. r_int) then
                  !it's inside the frozen zone, so
                  !just set tmp2 to zero and emit a warning
                  tmp2(i)=0.
                  if ((ip<=10).and.lheader) &
                       call warning('correct_for_selfgravity','Cannot '//&
                       'have centrifugal equilibrium in the inner '//&
                       'domain. Just warning...')
                else
                  print*,'correct_for_selfgravity: ',&
                       'cannot have centrifugal equilibrium in the inner ',&
                       'domain. The offending point is ',&
                       'x,y,z=',x(i+nghost),y(m),z(n)
                  print*,'the angular frequency here is ',tmp2(i)
                  call stop_it("")
                endif
              endif
            enddo
! 
!  Correct the velocities
!
            if (lcartesian_coords) then
              f(l1:l2,m,n,iux)=-sqrt(tmp2)*y(  m  )
              f(l1:l2,m,n,iuy)= sqrt(tmp2)*x(l1:l2)
            elseif (lcylindrical_coords) then
              f(l1:l2,m,n,iuy)= sqrt(tmp2)*rr_cyl
            elseif (lspherical_coords) then
              f(l1:l2,m,n,iuz)= sqrt(tmp2)*rr_sph*sinth(m)
            endif
          enddo
        enddo
      endif ! if (lselfgravity)
!
    endsubroutine correct_for_selfgravity    
!***********************************************************************
    subroutine power_law_gaussian_disk(f)
!
!  power-law with gaussian z
!
!  18/04/08/steveb: coded
!
      use Sub, only: get_radial_distance
      use Gravity, only: g0
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx) :: rr_sph,rr_cyl
      logical :: lheader
!
      if (lroot) print*,'setting density gradient of power '//&
          'law=',plaw
!
      do m=1,my
        do n=1,mz
          lheader=lroot.and.(m==1).and.(n==1)
          call get_radial_distance(rr_sph,rr_cyl)
          f(:,m,n,ilnrho) = & ! f(:,m,n,ilnrho) + &
              lnrho_const+0.5*log(r_ref/rr_cyl) &
              - z(n)**2.*g0/(2.*cs20*rr_cyl*3.)
        enddo
      enddo
!
      call impose_density_floor(f)
!
    endsubroutine power_law_gaussian_disk
!***********************************************************************
    subroutine power_law_disk(f)
!
!  Simple power-law disk. It sets only the density, whereas 
!  local_isothermal sets the density and thermodynamical
!  quantities
!
!  19-sep-07/wlad: coded
!
      use Sub, only: get_radial_distance
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx) :: rr_sph,rr_cyl
      logical :: lheader
!
      if (lroot) print*,'setting density gradient of power '//&
           'law=',plaw
!
      do m=1,my
        do n=1,mz
          lheader=lroot.and.(m==1).and.(n==1)
          call get_radial_distance(rr_sph,rr_cyl)
          f(:,m,n,ilnrho)=log(rho0)-.5*plaw*log((rr_cyl/r_ref)**2+rsmooth**2)
        enddo
      enddo
!
    endsubroutine power_law_disk
!***********************************************************************
    subroutine polytropic_simple(f)
!
!  Polytropic stratification (for lnrho and ss)
!  This routine should be independent of the gravity module used.
!
!  To maintain continuity with respect to the isothermal case,
!  one may want to specify cs20 (=1), and so zinfty is calculated from that.
!  On the other hand, for polytropic atmospheres it may be more
!  physical to specify zinfty (=1), ie the top of the polytropic atmosphere.
!  This is done if zinfty is different from 0.
!
!   8-jul-02/axel: incorporated/adapted from init_lnrho
!
      use Gravity, only: gravz_profile,gravz,zinfty,zref,zgrav,  &
                             potential,nu_epicycle
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: pot,dlncs2,r_mn
      real :: ggamma,ztop,zbot,zref2,pot_ext,lnrho_ref,ptop,pbot
!
!  identifier
!
      if (lroot) print*,'polytropic_simple: mpoly=',mpoly
!
!  The following is specific only to cases with gravity in the z direction
!  zref is calculated such that rho=rho0 and cs2=cs20 at z=zref.
!  Note: gravz is normally negative!
!
      if (lgravz) then
        if (gravz_profile=='const') then
          if (lroot.and.gravz==0.) print*,'polytropic_simple: divide by gravz=0'
          zref=zinfty-(mpoly+1.)*cs20/(-gamma*gravz)
        elseif (gravz_profile=='const_zero') then
          if (lroot.and.gravz==0.) print*,'polytropic_simple: divide by gravz=0'
          zref=zinfty-(mpoly+1.)*cs20/(-gamma*gravz)
        elseif (gravz_profile=='linear') then
          if (lroot.and.gravz==0.) print*,'polytropic_simple: divide by gravz=0'
          zref2=zinfty**2-(mpoly+1.)*cs20/(0.5*gamma*nu_epicycle**2)
          if (zref2<0) then
            if (lroot) print*,'polytropic_simple: zref**2<0 is not ok'
            zref2=0. !(and see what happens)
          endif
          zref=sqrt(zref2)
        else
          if (lroot) print*,'polytropic_simple: zref not prepared!'
        endif
        if (lroot) print*,'polytropic_simple: zref=',zref
!
!  check whether zinfty lies outside the domain (otherwise density
!  would vanish within the domain). At the moment we are not properly
!  testing the lower boundary on the case of a disc (commented out).
!
        ztop=xyz0(3)+Lxyz(3)
        zbot=xyz0(3)
        !-- if (zinfty<min(ztop,zgrav) .or. (-zinfty)>min(zbot,zgrav)) then
        if (zinfty<min(ztop,zgrav)) then
          if (lroot) print*,'polytropic_simple: domain too big; zinfty=',zinfty
          !call stop_it( &
          !         'polytropic_simply: rho and cs2 will vanish within domain')
        endif
      endif
!
!  stratification Gamma (upper case in the manual)
!
      ggamma=1.+1./mpoly
!
!  polytropic sphere with isothermal exterior
!  calculate potential at the stellar surface, pot_ext
!
      if (lgravr) then
        call potential(R=r_ext,POT=pot_ext)
        cs2top=-gamma/(mpoly+1.)*pot_ext
        lnrho_ref=mpoly*log(cs2top)-(mpoly+1.)
        print*,'polytropic_simple: pot_ext=',pot_ext
        do n=n1,n2; do m=m1,m2
          r_mn=sqrt(x(l1:l2)**2+y(m)**2+z(n)**2)
          call potential(x(l1:l2),y(m),z(n),pot=pot)
!
!  density
!  these formulae assume lnrho0=0 and cs0=1
!
          where (r_mn > r_ext)
            f(l1:l2,m,n,ilnrho)=lnrho_ref-gamma*pot/cs2top
          elsewhere
            dlncs2=log(-gamma*pot/((mpoly+1.)*cs20))
            f(l1:l2,m,n,ilnrho)=lnrho0+mpoly*dlncs2
          endwhere
!
!  entropy
!
          if (lentropy) then
            where (r_mn > r_ext)
              f(l1:l2,m,n,iss)=-(1.-1./gamma)*f(l1:l2,m,n,ilnrho)+log(cs2top)/gamma
            elsewhere
              dlncs2=log(-gamma*pot/((mpoly+1.)*cs20))
              f(l1:l2,m,n,iss)=mpoly*(ggamma/gamma-1.)*dlncs2
            endwhere
          endif
        enddo; enddo
      else
!
!  cartesian case with gravity in the z direction
!
        do n=n1,n2; do m=m1,m2
          call potential(x(l1:l2),y(m),z(n),pot=pot)
          dlncs2=log(-gamma*pot/((mpoly+1.)*cs20))
          f(l1:l2,m,n,ilnrho)=lnrho0+mpoly*dlncs2
          if (lentropy) f(l1:l2,m,n,iss)=mpoly*(ggamma/gamma-1.)*dlncs2
!         if (ltemperature) f(l1:l2,m,n,ilnTT)=dlncs2-log(gamma_m1)
          if (ltemperature) f(l1:l2,m,n,ilnTT)=log(-gamma*pot/(mpoly+1.)/gamma_m1)
        enddo; enddo
!
!  cs2 values at top and bottom may be needed to boundary conditions.
!  In spherical geometry, ztop is z at the outer edge of the box,
!  so this calculation still makes sense.
!
        call potential(xyz0(1),xyz0(2),ztop,pot=ptop)
        cs2top=-gamma*ptop/(mpoly+1.)
!
!  In spherical geometry ztop should never be used.
!  Even in slab geometry ztop is not normally used.
!
        call potential(xyz0(1),xyz0(2),zbot,pot=pbot)
        cs2bot=-gamma*pbot/(mpoly+1.)
      endif
!
    endsubroutine polytropic_simple
!***********************************************************************
    subroutine mass_source(f,df,p)
!
!  Add (isothermal) mass sources and sinks.
!
!  28-apr-2005/axel: coded
!
      use EquationOfState, only: gamma
      use Gravity, only: lnrho_bot,lnrho_top,ss_bot,ss_top
      use Sub, only: step
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
!
      real, dimension (nx) :: dlnrhodt,fint,fext,pdamp,fprofile,fnorm
!
      if (ldebug) print*,'mass_source: cs20,cs0=',cs20,cs0
!
!  Choose between different possibilities.
!
      if (mass_source_profile=='exponential') then
        dlnrhodt=mass_source_Mdot
      elseif (mass_source_profile=='bump') then
        fnorm=(2.*pi*mass_source_sigma**2)**1.5
        fprofile=exp(-.5*(p%r_mn/mass_source_sigma)**2)/fnorm
        dlnrhodt=mass_source_Mdot*fprofile
      elseif (mass_source_profile=='cylindric') then
!
!  Cylindrical profile for inner cylinder.
!
        pdamp=1-step(p%rcyl_mn,r_int,wdamp) ! inner damping profile
        fint=-damplnrho_int*pdamp*(f(l1:l2,m,n,ilnrho)-lnrho_int)
!
!  Cylindrical profile for outer cylinder.
!
        pdamp=step(p%rcyl_mn,r_ext,wdamp) ! outer damping profile
        fext=-damplnrho_ext*pdamp*(f(l1:l2,m,n,ilnrho)-lnrho_ext)
        dlnrhodt=fint+fext
      endif
!
!  Add mass source.
!
      if (ldensity_nolog) then
        df(l1:l2,m,n,irho)=df(l1:l2,m,n,irho)+p%rho*dlnrhodt
      else
        df(l1:l2,m,n,irho)=df(l1:l2,m,n,irho)+dlnrhodt
      endif
!
!  Change entropy to keep temperature constant.
!
      if (lentropy) df(l1:l2,m,n,iss)=df(l1:l2,m,n,iss)+(gamma_inv-1.0)*dlnrhodt
!
    endsubroutine mass_source
!***********************************************************************
    subroutine impose_density_floor(f)
!
!  Impose a minimum density by setting all lower densities to the minimum
!  value (density_floor). Useful for debugging purposes.
!
!  13-aug-2007/anders: implemented.
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
!
      real :: density_floor_log
      logical, save :: lfirstcall=.true.
!
      if (density_floor>0.) then
        if (lfirstcall) then
          density_floor_log=alog(density_floor)
          lfirstcall=.false.
        endif
!
        if (ldensity_nolog) then
          where (f(:,:,:,irho)<density_floor) f(:,:,:,irho)=density_floor
        else
          where (f(:,:,:,ilnrho)<density_floor_log) &
              f(:,:,:,ilnrho)=density_floor_log
        endif
      endif
!
    endsubroutine impose_density_floor
!***********************************************************************
    subroutine read_density_init_pars(unit,iostat)
!
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat
!
      if (present(iostat)) then
        read(unit,NML=density_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=density_init_pars,ERR=99)
      endif
!
99    return
!
    endsubroutine read_density_init_pars
!***********************************************************************
    subroutine write_density_init_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit,NML=density_init_pars)
!
    endsubroutine write_density_init_pars
!***********************************************************************
    subroutine read_density_run_pars(unit,iostat)
!
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat
!
      if (present(iostat)) then
        read(unit,NML=density_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=density_run_pars,ERR=99)
      endif
!
99    return
!
    endsubroutine read_density_run_pars
!***********************************************************************
    subroutine write_density_run_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit,NML=density_run_pars)
!
    endsubroutine write_density_run_pars
!***********************************************************************
    subroutine rprint_density(lreset,lwrite)
!
!  reads and registers print parameters relevant for compressible part
!
!   3-may-02/axel: coded
!  27-may-02/axel: added possibility to reset list
!
      use Diagnostics
!
      logical :: lreset
      logical, optional :: lwrite
!
      integer :: iname, inamex, inamey, inamez, inamexy, inamexz, irz, inamer
      logical :: lwr
!
      lwr = .false.
      if (present(lwrite)) lwr=lwrite
!
!  reset everything in case of reset
!  (this needs to be consistent with what is defined above!)
!
      if (lreset) then
        idiag_rhom=0; idiag_rho2m=0; idiag_lnrho2m=0
        idiag_drho2m=0; idiag_drhom=0
        idiag_ugrhom=0; idiag_uglnrhom=0
        idiag_rhomin=0; idiag_rhomax=0; idiag_dtd=0
        idiag_lnrhomphi=0; idiag_rhomphi=0
        idiag_rhomz=0; idiag_rhomy=0; idiag_rhomx=0 
        idiag_rhomxy=0; idiag_rhomr=0; idiag_totmass=0; idiag_mass=0
        idiag_rhomxz=0
      endif
!
!  iname runs through all possible names that may be listed in print.in
!
      if (lroot.and.ip<14) print*,'rprint_density: run through parse list'
      do iname=1,nname
        call parse_name(iname,cname(iname),cform(iname),'rhom',idiag_rhom)
        call parse_name(iname,cname(iname),cform(iname),'rho2m',idiag_rho2m)
        call parse_name(iname,cname(iname),cform(iname),'drho2m',idiag_drho2m)
        call parse_name(iname,cname(iname),cform(iname),'drhom',idiag_drhom)
        call parse_name(iname,cname(iname),cform(iname),'rhomin',idiag_rhomin)
        call parse_name(iname,cname(iname),cform(iname),'rhomax',idiag_rhomax)
        call parse_name(iname,cname(iname),cform(iname),'lnrho2m',idiag_lnrho2m)
        call parse_name(iname,cname(iname),cform(iname),'ugrhom',idiag_ugrhom)
        call parse_name(iname,cname(iname),cform(iname),'uglnrhom',idiag_uglnrhom)
        call parse_name(iname,cname(iname),cform(iname),'dtd',idiag_dtd)
        call parse_name(iname,cname(iname),cform(iname),'totmass',idiag_totmass)
        call parse_name(iname,cname(iname),cform(iname),'mass',idiag_mass)
      enddo
!
!  check for those quantities for which we want xy-averages
!
      do inamez=1,nnamez
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'rhomz',idiag_rhomz)
      enddo
!
!  check for those quantities for which we want xz-averages
!
      do inamey=1,nnamey
        call parse_name(inamey,cnamey(inamey),cformy(inamey),'rhomy',idiag_rhomy)
      enddo
!
!  check for those quantities for which we want yz-averages
!
      do inamex=1,nnamex
        call parse_name(inamex,cnamex(inamex),cformx(inamex),'rhomx',idiag_rhomx)
      enddo
!
!  check for those quantities for which we want phiz-averages
!
      do inamer=1,nnamer
        call parse_name(inamer,cnamer(inamer),cformr(inamer),'rhomr',idiag_rhomr)
      enddo
!
!  check for those quantities for which we want z-averages
!
      do inamexz=1,nnamexz
        call parse_name(inamexz,cnamexz(inamexz),cformxz(inamexz),'rhomxz',idiag_rhomxz)
      enddo
!
!  check for those quantities for which we want z-averages
!
      do inamexy=1,nnamexy
        call parse_name(inamexy,cnamexy(inamexy),cformxy(inamexy),'rhomxy',idiag_rhomxy)
      enddo
!
!  check for those quantities for which we want phi-averages
!
      do irz=1,nnamerz
        call parse_name(irz,cnamerz(irz),cformrz(irz),&
            'lnrhomphi',idiag_lnrhomphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'rhomphi',idiag_rhomphi)
      enddo
!
!  write column where which density variable is stored
!
      if (lwr) then
        write(3,*) 'i_rhom=',idiag_rhom
        write(3,*) 'i_rho2m=',idiag_rho2m
        write(3,*) 'i_drho2m=',idiag_drho2m
        write(3,*) 'i_drhom=',idiag_drhom
        write(3,*) 'i_rhomin=',idiag_rhomin
        write(3,*) 'i_rhomax=',idiag_rhomax
        write(3,*) 'i_lnrho2m=',idiag_lnrho2m
        write(3,*) 'i_ugrhom=',idiag_ugrhom
        write(3,*) 'i_uglnrhom=',idiag_uglnrhom
        write(3,*) 'i_rhomz=',idiag_rhomz
        write(3,*) 'i_rhomy=',idiag_rhomy
        write(3,*) 'i_rhomx=',idiag_rhomx
        write(3,*) 'i_rhomxy=',idiag_rhomxy
        write(3,*) 'i_rhomxz=',idiag_rhomxz
        write(3,*) 'nname=',nname
        write(3,*) 'ilnrho=',ilnrho
        write(3,*) 'irho=',irho
        write(3,*) 'i_lnrhomphi=',idiag_lnrhomphi
        write(3,*) 'i_rhomphi=',idiag_rhomphi
        write(3,*) 'i_rhomr=',idiag_rhomr
        write(3,*) 'i_dtd=',idiag_dtd
        write(3,*) 'i_totmass=',idiag_totmass
        write(3,*) 'i_mass=',idiag_mass
      endif
!
    endsubroutine rprint_density
!***********************************************************************
    subroutine get_slices_density(f,slices)
!
!  Write slices for animation of Density variables.
!
!  26-jul-06/tony: coded
!
      real, dimension (mx,my,mz,mfarray) :: f
      type (slice_data) :: slices
!
!  Loop over slices
!
      select case (trim(slices%name))
!
!  Density.
!
        case ('rho')
          if (ldensity_nolog) then
            slices%yz =f(ix_loc,m1:m2,n1:n2,irho)
            slices%xz =f(l1:l2,iy_loc,n1:n2,irho)
            slices%xy =f(l1:l2,m1:m2,iz_loc,irho)
            slices%xy2=f(l1:l2,m1:m2,iz2_loc,irho)
            if (lwrite_slice_xy3) slices%xy3=f(l1:l2,m1:m2,iz3_loc,irho)
            if (lwrite_slice_xy4) slices%xy4=f(l1:l2,m1:m2,iz4_loc,irho)
            slices%ready=.true.
          else
            slices%yz =exp(f(ix_loc,m1:m2,n1:n2,ilnrho))
            slices%xz =exp(f(l1:l2,iy_loc,n1:n2,ilnrho))
            slices%xy =exp(f(l1:l2,m1:m2,iz_loc,ilnrho))
            slices%xy2=exp(f(l1:l2,m1:m2,iz2_loc,ilnrho))
            if (lwrite_slice_xy3) slices%xy3=exp(f(l1:l2,m1:m2,iz3_loc,ilnrho))
            if (lwrite_slice_xy4) slices%xy4=exp(f(l1:l2,m1:m2,iz4_loc,ilnrho))
            slices%ready=.true.
          endif
!
!  Logarithmic density.
!
        case ('lnrho')
          if (ldensity_nolog) then
            slices%yz =alog(f(ix_loc,m1:m2,n1:n2,irho))
            slices%xz =alog(f(l1:l2,iy_loc,n1:n2,irho))
            slices%xy =alog(f(l1:l2,m1:m2,iz_loc,irho))
            slices%xy2=alog(f(l1:l2,m1:m2,iz2_loc,irho))
            if (lwrite_slice_xy3) slices%xy3=alog(f(l1:l2,m1:m2,iz3_loc,irho))
            if (lwrite_slice_xy4) slices%xy4=alog(f(l1:l2,m1:m2,iz4_loc,irho))
            slices%ready=.true.
          else
            slices%yz =f(ix_loc,m1:m2,n1:n2,ilnrho)
            slices%xz =f(l1:l2,iy_loc,n1:n2,ilnrho)
            slices%xy =f(l1:l2,m1:m2,iz_loc,ilnrho)
            slices%xy2=f(l1:l2,m1:m2,iz2_loc,ilnrho)
            if (lwrite_slice_xy3) slices%xy3=f(l1:l2,m1:m2,iz3_loc,ilnrho)
            if (lwrite_slice_xy4) slices%xy4=f(l1:l2,m1:m2,iz4_loc,ilnrho)
            slices%ready=.true.
          endif
!
      endselect
!
    endsubroutine get_slices_density
!***********************************************************************
endmodule Density
