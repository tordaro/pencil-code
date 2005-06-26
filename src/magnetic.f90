! $Id: magnetic.f90,v 1.242 2005-06-26 17:34:13 eos_merger_tony Exp $

!  This modules deals with all aspects of magnetic fields; if no
!  magnetic fields are invoked, a corresponding replacement dummy
!  routine is used instead which absorbs all the calls to the
!  magnetically relevant subroutines listed in here.

!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! CPARAM logical, parameter :: lmagnetic = .true.
!
! MVAR CONTRIBUTION 3
! MAUX CONTRIBUTION 0
!
! PENCILS PROVIDED aa,a2,aij,bb,ab,uxb,b2,bij,del2a,graddiva,jj
! PENCILS PROVIDED j2,jb,va2,jxb,jxbr,ub,uxb,uxb2,uxj,beta
! PENCILS PROVIDED djuidjbi,jo,ujxb,oxu,oxuxb,jxbxb,jxbrxb
! PENCILS PROVIDED glnrhoxb,del4a,del6a,oxj,diva,jij,sj,ss12 
! PENCILS PROVIDED mf_EMF, mf_EMFdotB,gradcurla
!
!***************************************************************

module Magnetic

  use Cparam

  implicit none

  include 'magnetic.inc'

  character (len=labellen) :: initaa='zero',initaa2='zero'
  character (len=labellen) :: iresistivity='eta-const',Omega_profile='nothing'
  ! input parameters
  real, dimension(3) :: B_ext=(/0.,0.,0./),B_ext_tmp
  real, dimension(3) :: axisr1=(/0,0,1/),dispr1=(/0.,0.5,0./)
  real, dimension(3) :: axisr2=(/1,0,0/),dispr2=(/0.,-0.5,0./)
  real :: fring1=0.,Iring1=0.,Rring1=1.,wr1=0.3
  real :: fring2=0.,Iring2=0.,Rring2=1.,wr2=0.3
  real :: amplaa=0., kx_aa=1.,ky_aa=1.,kz_aa=1.
  real :: radius=.1,epsilonaa=1e-2,widthaa=.5,x0aa=0.,z0aa=0.
  real :: by_left=0.,by_right=0.,bz_left=0.,bz_right=0.
  real :: ABC_A=1.,ABC_B=1.,ABC_C=1.
  real :: amplaa2=0.,kx_aa2=impossible,ky_aa2=impossible,kz_aa2=impossible
  real :: bthresh=0.,bthresh_per_brms=0.,brms=0.,bthresh_scl=1.
  real :: eta_shock=0.
  real :: rhomin_jxb=0.,va2max_jxb=0.
  real :: omega_Bz_ext=0.
  real :: mu_r=-0.5 !(still needed for backwards compatibility)
  real :: mu_ext_pot=-0.5
  real :: rescale_aa=1.
  real :: ampl_B0=0.,D_smag=0.17,B_ext21
  real :: Omega_ampl
  integer :: nbvec,nbvecmax=nx*ny*nz/4,va2power_jxb=5
  logical :: lpress_equil=.false., lpress_equil_via_ss=.false.
  logical :: llorentzforce=.true.,linduction=.true.
  ! dgm: for hyper diffusion in any spatial variation of eta
  logical :: lresistivity_hyper=.false.
!ajwm - Unused???
!    logical :: leta_const=.true.
  logical :: lfrozen_bz_z_bot=.false.,lfrozen_bz_z_top=.false.
  logical :: reinitalize_aa=.false.
  logical :: lB_ext_pot=.false.
  logical :: lee_ext=.false.,lbb_ext=.false.,ljj_ext=.false.
  logical :: lforce_free_test=.false.
  logical :: lmeanfield_theory=.false.,lOmega_effect=.false.
  real :: nu_ni=0.,nu_ni1,hall_term=0.
  real :: alpha_effect=0.,alpha_quenching=0.,delta_effect=0.,meanfield_etat=0.
  real :: displacement_gun=0.
  complex, dimension(3) :: coefaa=(/0.,0.,0./), coefbb=(/0.,0.,0./)
  ! dgm: for perturbing magnetic field when reading NON-magnetic snapshot
  real :: pertamplaa=0.
  real :: initpower_aa=0.,cutoff_aa=0.,brms_target=1.,rescaling_fraction=1.
  character (len=labellen) :: pertaa='zero'
  integer :: N_modes_aa=1

  namelist /magnetic_init_pars/ &
       B_ext, &
       fring1,Iring1,Rring1,wr1,axisr1,dispr1, &
       fring2,Iring2,Rring2,wr2,axisr2,dispr2, &
       radius,epsilonaa,x0aa,z0aa,widthaa, &
       by_left,by_right,bz_left,bz_right, &
       initaa,initaa2,amplaa,amplaa2,kx_aa,ky_aa,kz_aa,coefaa,coefbb, &
       kx_aa2,ky_aa2,kz_aa2,lpress_equil,lpress_equil_via_ss,mu_r, &
       mu_ext_pot,lB_ext_pot,lforce_free_test, &
       ampl_B0,initpower_aa,cutoff_aa,N_modes_aa

  ! run parameters
  real :: eta=0.,height_eta=0.,eta_out=0.
  real :: eta_int=0.,eta_ext=0.,wresistivity=.01
  real :: tau_aa_exterior=0.

  namelist /magnetic_run_pars/ &
       eta,B_ext,omega_Bz_ext,nu_ni,hall_term, &
       lmeanfield_theory,alpha_effect,alpha_quenching,delta_effect, &
       meanfield_etat, &
       height_eta,eta_out,tau_aa_exterior, &
       kx_aa,ky_aa,kz_aa,ABC_A,ABC_B,ABC_C, &
       bthresh,bthresh_per_brms, &
       iresistivity,lresistivity_hyper, &
       eta_int,eta_ext,eta_shock,wresistivity, &
       rhomin_jxb,va2max_jxb,va2power_jxb,llorentzforce,linduction, &
       reinitalize_aa,rescale_aa,lB_ext_pot, &
       lee_ext,lbb_ext,ljj_ext,displacement_gun, &
       pertaa,pertamplaa,D_smag,brms_target,rescaling_fraction, &
       lOmega_effect,Omega_profile,Omega_ampl

  ! other variables (needs to be consistent with reset list below)
  integer :: idiag_b2m=0,idiag_bm2=0,idiag_j2m=0,idiag_jm2=0
  integer :: idiag_abm=0,idiag_jbm=0,idiag_ubm=0,idiag_epsM=0
  integer :: idiag_bxpt=0,idiag_bypt=0,idiag_bzpt=0,idiag_epsM_LES=0
  integer :: idiag_aybym2=0,idiag_exaym2=0,idiag_exjm2=0
  integer :: idiag_brms=0,idiag_bmax=0,idiag_jrms=0,idiag_jmax=0
  integer :: idiag_vArms=0,idiag_vAmax=0,idiag_dtb=0
  integer :: idiag_arms=0,idiag_amax=0,idiag_beta1m=0,idiag_beta1max=0
  integer :: idiag_bx2m=0,idiag_by2m=0,idiag_bz2m=0
  integer :: idiag_bxbym=0,idiag_bxbzm=0,idiag_bybzm=0,idiag_djuidjbim=0
  integer :: idiag_bxmz=0,idiag_bymz=0,idiag_bzmz=0,idiag_bmx=0
  integer :: idiag_bmy=0,idiag_bmz=0
  integer :: idiag_bxmxy=0,idiag_bymxy=0,idiag_bzmxy=0
  integer :: idiag_bxmxz=0,idiag_bymxz=0,idiag_bzmxz=0
  integer :: idiag_uxbm=0,idiag_oxuxbm=0,idiag_jxbxbm=0,idiag_gpxbm=0
  integer :: idiag_uxDxuxbm=0,idiag_b2b13m=0,idiag_jbmphi=0,idiag_dteta=0
  integer :: idiag_uxbmx=0,idiag_uxbmy=0,idiag_uxbmz=0,idiag_uxjm=0
  integer :: idiag_brmphi=0,idiag_bpmphi=0,idiag_bzmphi=0,idiag_b2mphi=0
  integer :: idiag_uxbrmphi=0,idiag_uxbpmphi=0,idiag_uxbzmphi=0,idiag_ujxbm=0
  integer :: idiag_uxBrms=0,idiag_Bresrms=0,idiag_Rmrms=0
!merge_axel: not sure whether I missed any of the following from trunk...
! integer :: i_b2m=0,i_bm2=0,i_j2m=0,i_jm2=0,i_abm=0,i_jbm=0,i_ubm,i_epsM=0
! integer :: i_bxpt=0,i_bypt=0,i_bzpt=0,i_epsM_LES=0
! integer :: i_aybym2=0,i_exaym2=0,i_exjm2=0
! integer :: i_brms=0,i_bmax=0,i_jrms=0,i_jmax=0,i_vArms=0,i_vAmax=0,i_dtb=0
! integer :: i_beta1m=0,i_beta1max=0
! integer :: i_bx2m=0, i_by2m=0, i_bz2m=0
! integer :: i_bxbym=0, i_bxbzm=0, i_bybzm=0,i_djuidjbim
! integer :: i_bxmz=0,i_bymz=0,i_bzmz=0,i_bmx=0,i_bmy=0,i_bmz=0
! integer :: i_bxmxy=0,i_bymxy=0,i_bzmxy=0
! integer :: i_bxmxz=0,i_bymxz=0,i_bzmxz=0
! integer :: i_uxbm=0,i_oxuxbm=0,i_jxbxbm=0,i_gpxbm=0,i_uxDxuxbm=0
! integer :: i_uxbmx=0,i_uxbmy=0,i_uxbmz=0,i_uxjm=0,i_ujxbm
! integer :: i_b2b13m=0
! integer :: i_brmphi=0,i_bpmphi=0,i_bzmphi=0,i_b2mphi=0,i_jbmphi=0
! integer :: i_uxbrmphi,i_uxbpmphi,i_uxbzmphi
! integer :: i_dteta=0

  contains

!***********************************************************************
    subroutine register_magnetic()
!
!  Initialise variables which should know that we solve for the vector
!  potential: iaa, etc; increase nvar accordingly
!
!  1-may-02/wolf: coded
!
      use Cdata
      use Mpicomm
      use Sub
!
      logical, save :: first=.true.
!
      if (.not. first) call stop_it('register_aa called twice')
      first = .false.
!
      iaa = nvar+1              ! indices to access aa
      iax = iaa
      iay = iaa+1
      iaz = iaa+2
      nvar = nvar+3             ! added 3 variables
!
      if ((ip<=8) .and. lroot) then
        print*, 'register_magnetic: nvar = ', nvar
        print*, 'register_magnetic: iaa,iax,iay,iaz = ', iaa,iax,iay,iaz
      endif
!
!  Put variable names in array
!
      varname(iax) = 'ax'
      varname(iay) = 'ay'
      varname(iaz) = 'az'
!
!  identify version number
!
      if (lroot) call cvs_id( &
           "$Id: magnetic.f90,v 1.242 2005-06-26 17:34:13 eos_merger_tony Exp $")
!
      if (nvar > mvar) then
        if (lroot) write(0,*) 'nvar = ', nvar, ', mvar = ', mvar
        call stop_it('register_magnetic: nvar > mvar')
      endif
!
!  Writing files for use with IDL
!
      if (lroot) then
        if (maux == 0) then
          if (nvar < mvar) write(4,*) ',aa $'
          if (nvar == mvar) write(4,*) ',aa'
        else
          write(4,*) ',aa $'
        endif
        write(15,*) 'aa = fltarr(mx,my,mz,3)*one'
      endif
!
    endsubroutine register_magnetic
!***********************************************************************
    subroutine initialize_magnetic(f)
!
!  Perform any post-parameter-read initialization
!
!  24-nov-02/tony: dummy routine - nothing to do at present
!  20-may-03/axel: reinitalize_aa added
!
      use Cdata
!
      real, dimension (mx,my,mz,mvar+maux) :: f
!
!  Precalculate 1/mu (moved here from register.f90)
!
      mu01=1./mu0
!
!  Precalculate 1/nu_ni
!
      nu_ni1=1./nu_ni
!
!  calculate B_ext21
!
      B_ext21=B_ext(1)**2+B_ext(2)**2+B_ext(3)**2
      if (B_ext21/=0.) then
        B_ext21=1./B_ext21
      else
        B_ext21=1.
      endif
!
!  set to zero and then rescale the magnetic field
!  (in future, could call something like init_aa_simple)
!
      if (reinitalize_aa) then
        f(:,:,:,iax:iaz)=rescale_aa*f(:,:,:,iax:iaz)
      endif
!
    endsubroutine initialize_magnetic
!***********************************************************************
    subroutine init_aa(f,xx,yy,zz)
!
!  initialise magnetic field; called from start.f90
!  AB: maybe we should here call different routines (such as rings)
!  AB: and others, instead of accummulating all this in a huge routine.
!  We have an init parameter (initaa) to stear magnetic i.c. independently.
!
!   7-nov-2001/wolf: coded
!
      use Cdata
      use Mpicomm
      use EquationOfState
      use Gravity, only: gravz
      use Sub
      use Initcond
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz)      :: xx,yy,zz,tmp,prof
      real, dimension (nx,3) :: bb
      real, dimension (nx) :: b2,fact
      real :: beq2
!
      select case(initaa)

      case('zero', '0'); f(:,:,:,iax:iaz) = 0.
      case('rescale'); f(:,:,:,iax:iaz)=amplaa*f(:,:,:,iax:iaz)
      case('mode'); call modev(amplaa,coefaa,f,iaa,kx_aa,ky_aa,kz_aa,xx,yy,zz)
      case('modeb'); call modeb(amplaa,coefbb,f,iaa,kx_aa,ky_aa,kz_aa,xx,yy,zz)
      case('power_randomphase')
         call power_randomphase(amplaa,initpower_aa,cutoff_aa,f,iax,iaz)
      case('random-isotropic-KS')
         call random_isotropic_KS(amplaa,initpower_aa,cutoff_aa,f,iax,iaz,N_modes_aa)
      case('gaussian-noise'); call gaunoise(amplaa,f,iax,iaz)
      case('gaussian-noise-rprof')
        tmp=sqrt(xx**2+yy**2+zz**2)
        call gaunoise_rprof(amplaa,tmp,prof,f,iax,iaz)
      case('Beltrami-x', '11'); call beltrami(amplaa,f,iaa,KX=kx_aa)
      case('Beltrami-y', '12'); call beltrami(amplaa,f,iaa,KY=ky_aa)
      case('Beltrami-z', '1');  call beltrami(amplaa,f,iaa,KZ=kz_aa)
      case('propto-ux'); call wave_uu(amplaa,f,iaa,kx=kx_aa)
      case('propto-uy'); call wave_uu(amplaa,f,iaa,ky=ky_aa)
      case('propto-uz'); call wave_uu(amplaa,f,iaa,kz=kz_aa)
      case('diffrot'); call diffrot(amplaa,f,iay,xx,yy,zz)
      case('hor-tube'); call htube(amplaa,f,iax,iaz,xx,yy,zz,radius,epsilonaa)
      case('hor-fluxlayer'); call hfluxlayer(amplaa,f,iaa,xx,yy,zz,z0aa,widthaa)
      case('ver-fluxlayer'); call vfluxlayer(amplaa,f,iaa,xx,yy,zz,x0aa,widthaa)
      case('mag-support'); call magsupport(amplaa,f,zz,gravz,cs0,rho0)
      case('arcade-x'); call arcade_x(amplaa,f,iaa,xx,yy,zz,kx_aa,kz_aa)
      case('halfcos-Bx'); call halfcos_x(amplaa,f,iaa,xx,yy,zz)
      case('uniform-Bx'); call uniform_x(amplaa,f,iaa,xx,yy,zz)
      case('uniform-By'); call uniform_y(amplaa,f,iaa,xx,yy,zz)
      case('uniform-Bz'); call uniform_z(amplaa,f,iaa,xx,yy,zz)
      case('Bz(x)', '3'); call vfield(amplaa,f,iaa,xx)
      case('vfield2'); call vfield2(amplaa,f,iaa,xx)
      case('xjump'); call bjump(f,iaa,by_left,by_right,bz_left,bz_right,widthaa,'x')
      case('fluxrings', '4'); call fluxrings(f,iaa,xx,yy,zz)
      case('sinxsinz'); call sinxsinz(amplaa,f,iaa,kx_aa,ky_aa,kz_aa)
      case('sin2xsin2y'); call sin2x_sin2y_cosz(amplaa,f,iaz,kx_aa,ky_aa,0.)
      case('cosxcosy'); call cosx_cosy_cosz(amplaa,f,iaz,kx_aa,ky_aa,0.)
      case('sinxsiny'); call sinx_siny_cosz(amplaa,f,iaz,kx_aa,ky_aa,0.)
      case('cosxcoscosy'); call cosx_coscosy_cosz(amplaa,f,iaz,kx_aa,ky_aa,0.)
      case('crazy', '5'); call crazy(amplaa,f,iaa)
      case('Alfven-x'); call alfven_x(amplaa,f,iuu,iaa,ilnrho,xx,kx_aa)
      case('Alfven-z'); call alfven_z(amplaa,f,iuu,iaa,zz,kz_aa,mu0)
      case('Alfvenz-rot'); call alfvenz_rot(amplaa,f,iuu,iaa,zz,kz_aa,Omega)
      case('Alfvenz-rot-shear'); call alfvenz_rot_shear(amplaa,f,iuu,iaa,zz,kz_aa,Omega)
      case('tony-nohel')
        f(:,:,:,iay) = amplaa/kz_aa*cos(kz_aa*2.*pi/Lz*zz)
      case('tony-nohel-yz')
        f(:,:,:,iay) = amplaa/kx_aa*sin(kx_aa*2.*pi/Lx*xx)
      case('tony-hel-xy')
        f(:,:,:,iax) = amplaa/kz_aa*sin(kz_aa*2.*pi/Lz*zz)
        f(:,:,:,iay) = amplaa/kz_aa*cos(kz_aa*2.*pi/Lz*zz)
      case('tony-hel-yz')
        f(:,:,:,iay) = amplaa/kx_aa*sin(kx_aa*2.*pi/Lx*xx)
        f(:,:,:,iaz) = amplaa/kx_aa*cos(kx_aa*2.*pi/Lx*xx)
      case('force-free-jet')
        lB_ext_pot=.true.
        call force_free_jet(mu_ext_pot,xx,yy,zz)
      case('Alfven-circ-x')
        !
        !  circularly polarised Alfven wave in x direction
        !
        if (lroot) print*,'init_aa: circular Alfven wave -> x'
        f(:,:,:,iay) = amplaa/kx_aa*sin(kx_aa*xx)
        f(:,:,:,iaz) = amplaa/kx_aa*cos(kx_aa*xx)
      case('geo-benchmark-case1','geo-benchmark-case2'); call geo_benchmark_B(f)

      case default
        !
        !  Catch unknown values
        !
        if (lroot) print*, 'init_aa: No such value for initaa: ', trim(initaa)
        call stop_it("")

      endselect
!
!    If not already used in initaa one can still use kx_aa etc. 
!    to define the wavenumber of the 2nd field. (For old runs!)
!
       if (kx_aa2==impossible) kx_aa2 = kx_aa
       if (ky_aa2==impossible) ky_aa2 = ky_aa
       if (kz_aa2==impossible) kz_aa2 = kz_aa
!
!  superimpose something else
!
      select case(initaa2)
        case('Beltrami-x'); call beltrami(amplaa2,f,iaa,KX=kx_aa2)
        case('Beltrami-y'); call beltrami(amplaa2,f,iaa,KY=ky_aa2)
        case('Beltrami-z'); call beltrami(amplaa2,f,iaa,KZ=kz_aa2)      
        case('gaussian-noise'); call gaunoise(amplaa2,f,iax,iaz)
      endselect
!
!  allow for pressure equilibrium (for isothermal tube)
!  assume that ghost zones have already been set.
!  corrected expression below for gamma /= 1 case.
!  The beq2 expression for 2*mu0*p is not general yet.
!
      if (lpress_equil.or.lpress_equil_via_ss) then
        if (lroot) print*,'init_aa: adjust lnrho to have pressure equilib; cs0=',cs0
        do n=n1,n2
        do m=m1,m2
          call curl(f,iaa,bb)
          call dot2_mn(bb,b2)
          if (gamma==1.) then
            f(l1:l2,m,n,ilnrho)=f(l1:l2,m,n,ilnrho)-b2/(2.*cs0**2)
          else
            beq2=2.*rho0*cs0**2
            fact=max(1e-6,1.-b2/beq2)
            if (lentropy.and.lpress_equil_via_ss) then
              f(l1:l2,m,n,iss)=f(l1:l2,m,n,iss)+fact/gamma
            else
              f(l1:l2,m,n,ilnrho)=f(l1:l2,m,n,ilnrho)+fact/gamma1
            endif
          endif
        enddo
        enddo
      endif
!
    endsubroutine init_aa
!***********************************************************************
    subroutine pert_aa(f)
!
!   perturb magnetic field when reading old NON-magnetic snapshot
!   called from run.f90
!   30-july-2004/dave: coded
!
      use Cdata
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: xx,yy,zz
!
      xx=spread(spread(x,2,my),3,mz)
      yy=spread(spread(y,1,mx),3,mz)
      zz=spread(spread(z,1,mx),2,my)
      initaa=pertaa
      amplaa=pertamplaa
      call init_aa(f,xx,yy,zz)
!
    endsubroutine pert_aa
!***********************************************************************
    subroutine pencil_criteria_magnetic()
!
!   All pencils that the Magnetic module depends on are specified here.
!
!  19-11-04/anders: coded
!
      use Cdata
!      
      lpenc_requested(i_bb)=.true.
      lpenc_requested(i_uxb)=.true.
!
      if (dvid/=0.0) lpenc_video(i_b2)=.true.
!      
      if ( (hall_term/=0. .and. ldt) .or. height_eta/=0. .or. ip<=4) &
          lpenc_requested(i_jj)=.true.
      if (dvid/=0.) lpenc_video(i_jb)=.true.
      if (iresistivity=='eta-const' .or. iresistivity=='shell' .or. &
          iresistivity=='shock' .or. iresistivity=='Smagorinsky' .or. &
          iresistivity=='Smagorinsky_cross') lpenc_requested(i_del2a)=.true.
      if (iresistivity=='shock') then
        lpenc_requested(i_gshock)=.true.
        lpenc_requested(i_shock)=.true.
      endif
      if (iresistivity=='shock' .or. iresistivity=='shell') &
          lpenc_requested(i_diva)=.true.
      if (iresistivity=='Smagorinsky_cross') lpenc_requested(i_jo)=.true.
      if (iresistivity=='hyper2') lpenc_requested(i_del4a)=.true.
      if (iresistivity=='hyper3') lpenc_requested(i_del6a)=.true.
      if (lspherical) lpenc_requested(i_graddiva)=.true.
      if (lentropy .or. iresistivity=='Smagorinsky') &
          lpenc_requested(i_j2)=.true.
      if (lentropy .or. ldt) lpenc_requested(i_rho1)=.true.
      if (lentropy) lpenc_requested(i_TT1)=.true.
      if (nu_ni/=0.) lpenc_requested(i_va2)=.true.
      if (hall_term/=0.) lpenc_requested(i_jxb)=.true.
      if ((lhydro .and. llorentzforce) .or. nu_ni/=0.) &
          lpenc_requested(i_jxbr)=.true.
      if (iresistivity=='Smagorinsky_cross' .or. delta_effect/=0.) &
          lpenc_requested(i_oo)=.true.
      if (nu_ni/=0.) lpenc_requested(i_va2)=.true.
      if (lmeanfield_theory) then
        if (alpha_effect/=0. .or. delta_effect/=0.) lpenc_requested(i_mf_EMF)=.true.
        if (delta_effect/=0.) lpenc_requested(i_oxj)=.true.
      endif
      if (nu_ni/=0.) lpenc_diagnos(i_jxbrxb)=.true.
!
      if (idiag_aybym2/=0 .or. idiag_exaym2/=0) lpenc_diagnos(i_aa)=.true.
      if (idiag_arms/=0 .or. idiag_amax/=0) lpenc_diagnos(i_a2)=.true.
      if (idiag_abm/=0) lpenc_diagnos(i_ab)=.true.
      if (idiag_djuidjbim/=0 .or. idiag_b2b13m/=0) &
          lpenc_diagnos(i_bij)=.true.
      if (idiag_j2m/=0 .or. idiag_jm2/=0 .or. idiag_jrms/=0 .or. &
          idiag_jmax/=0 .or. idiag_epsM/=0 .or. idiag_epsM_LES/=0) &
          lpenc_diagnos(i_j2)=.true.
      if (idiag_jbm/=0) lpenc_diagnos(i_jb)=.true.
      if (idiag_jbmphi/=0) lpenc_diagnos2d(i_jb)=.true.
      if (idiag_vArms/=0 .or. idiag_vAmax/=0) lpenc_diagnos(i_va2)=.true.
      if (idiag_ubm/=0) lpenc_diagnos(i_ub)=.true.
      if (idiag_djuidjbim/=0 .or. idiag_uxDxuxbm/=0) lpenc_diagnos(i_uij)=.true.
      if (idiag_uxjm/=0) lpenc_diagnos(i_uxj)=.true.
      if (idiag_vArms/=0 .or. idiag_vAmax/=0) lpenc_diagnos(i_va2)=.true.
      if (idiag_uxBrms/=0 .or. idiag_Rmrms/=0) lpenc_diagnos(i_uxb2)=.true.
      if (idiag_beta1m/=0 .or. idiag_beta1max/=0) lpenc_diagnos(i_beta)=.true.
      if (idiag_djuidjbim/=0) lpenc_diagnos(i_djuidjbi)=.true.
      if (idiag_ujxbm/=0) lpenc_diagnos(i_ujxb)=.true.
      if (idiag_gpxbm/=0) lpenc_diagnos(i_glnrhoxb)=.true.
      if (idiag_jxbxbm/=0) lpenc_diagnos(i_jxbxb)=.true.
      if (idiag_oxuxbm/=0) lpenc_diagnos(i_oxuxb)=.true.
      if (idiag_exaym2/=0 .or. idiag_exjm2/=0) lpenc_diagnos(i_jj)=.true.
      if (idiag_b2m/=0 .or. idiag_bm2/=0 .or. idiag_brms/=0 .or. &
          idiag_bmax/=0) lpenc_diagnos(i_b2)=.true.
!
    endsubroutine pencil_criteria_magnetic
!***********************************************************************
    subroutine pencil_interdep_magnetic(lpencil_in)
!
!  Interdependency among pencils from the Magnetic module is specified here.
!
!  19-11-04/anders: coded
!
      use Cdata
!
      logical, dimension(npencils) :: lpencil_in
!
      if (lpencil_in(i_a2)) lpencil_in(i_aa)=.true.
      if (lpencil_in(i_ab)) then
        lpencil_in(i_aa)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_va2)) then
        lpencil_in(i_b2)=.true.
        lpencil_in(i_rho1)=.true.
      endif
      if (lpencil_in(i_j2)) lpencil_in(i_jj)=.true.
      if (lpencil_in(i_uxj)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_jj)=.true.
      endif
      if (lpencil_in(i_jb)) then
        lpencil_in(i_bb)=.true.
        lpencil_in(i_jj)=.true.
      endif
      if (lpencil_in(i_jxbr) .and. va2max_jxb>0) lpencil_in(i_va2)=.true.
      if (lpencil_in(i_jxbr)) then
        lpencil_in(i_jxb)=.true.
        lpencil_in(i_rho1)=.true.
      endif
      if (lpencil_in(i_jxb)) then
        lpencil_in(i_jj)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_uxb2)) lpencil_in(i_uxb)=.true.
      if (lpencil_in(i_uxb)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_ub)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_beta)) then
        lpencil_in(i_b2)=.true.
        lpencil_in(i_pp)=.true.
      endif
      if (lpencil_in(i_b2)) lpencil_in(i_bb)=.true.
      if (lpencil_in(i_jj)) lpencil_in(i_bij)=.true.
      if (lpencil_in(i_bb)) then
        if (lspherical) lpencil_in(i_aa)=.true.
        lpencil_in(i_aij)=.true.
      endif
      if (lpencil_in(i_djuidjbi)) then
        lpencil_in(i_uij)=.true.
        lpencil_in(i_bij)=.true.
      endif
      if (lpencil_in(i_jo)) then
        lpencil_in(i_oo)=.true.
        lpencil_in(i_jj)=.true.
      endif
      if (lpencil_in(i_ujxb)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_jxb)=.true.
      endif
      if (lpencil_in(i_oxu)) then
        lpencil_in(i_oo)=.true.
        lpencil_in(i_uu)=.true.
      endif
      if (lpencil_in(i_oxuxb)) then
        lpencil_in(i_oxu)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_jxbxb)) then
        lpencil_in(i_jxb)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_jxbrxb)) then
        lpencil_in(i_jxbr)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_glnrhoxb)) then
        lpencil_in(i_glnrho)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_oxj)) then
        lpencil_in(i_oo)=.true.
        lpencil_in(i_jj)=.true.
      endif
      if (lpencil_in(i_jij)) lpencil_in(i_bij)=.true.
      if (lpencil_in(i_sj)) then
        lpencil_in(i_sij)=.true.
        lpencil_in(i_jij)=.true.
      endif
      if (lpencil_in(i_ss12)) lpencil_in(i_sij)=.true.
      if (lpencil_in(i_mf_EMFdotB)) then
        lpencil_in(i_mf_EMF)=.true.
        lpencil_in(i_bb)=.true.
      endif
      if (lpencil_in(i_mf_EMF)) then
        lpencil_in(i_b2)=.true.
        lpencil_in(i_bb)=.true.
        if (delta_effect/=0.) lpencil_in(i_oxJ)=.true.
        if (meanfield_etat/=0.) lpencil_in(i_jj)=.true.
      endif
      if (lpencil_in(i_del2A)) then
        if (lspherical) then
          lpencil_in(i_jj)=.true.
          lpencil_in(i_graddivA)=.true.
        endif
      endif
!
    endsubroutine pencil_interdep_magnetic
!***********************************************************************
    subroutine calc_pencils_magnetic(f,p)
!
!  Calculate Magnetic pencils.
!  Most basic pencils should come first, as others may depend on them.
!
!  19-nov-04/anders: coded
!
      use Cdata
      use Sub
      use Deriv
      use Global, only: get_global
!
      real, dimension (mx,my,mz,mvar+maux) :: f       
      type (pencil_case) :: p
!      
      real, dimension (nx,3) :: bb_ext,bb_ext_pot,ee_ext,jj_ext
      real, dimension (nx) :: rho1_jxb,quenching_factor,alpha_total
      real :: B2_ext,c,s
      integer :: i,j
!
      intent(in)  :: f
      intent(inout) :: p
! aa
      if (lpencil(i_aa)) p%aa=f(l1:l2,m,n,iax:iaz)
! a2
      if (lpencil(i_a2)) call dot2_mn(p%aa,p%a2)
! aij
      if (lpencil(i_aij)) call gij(f,iaa,p%aij,1)
! diva
      if (lpencil(i_diva)) call div(f,iaa,p%diva)
! bb
      if (lpencil(i_bb)) then
        call curl_mn(p%aij,p%bb,p%aa)
        B2_ext=B_ext(1)**2+B_ext(2)**2+B_ext(3)**2
!
!  allow external field to precess about z-axis
!  with frequency omega_Bz_ext
!
        if (B2_ext/=0.) then
          if (omega_Bz_ext==0.) then
            B_ext_tmp=B_ext
          elseif (omega_Bz_ext/=0.) then
            c=cos(omega_Bz_ext*t)
            s=sin(omega_Bz_ext*t)
            B_ext_tmp(1)=B_ext(1)*c-B_ext(2)*s
            B_ext_tmp(2)=B_ext(1)*s+B_ext(2)*c
            B_ext_tmp(3)=B_ext(3)
          endif
!  add the external field
          if (B_ext(1)/=0.) p%bb(:,1)=p%bb(:,1)+B_ext_tmp(1)
          if (B_ext(2)/=0.) p%bb(:,2)=p%bb(:,2)+B_ext_tmp(2)
          if (B_ext(3)/=0.) p%bb(:,3)=p%bb(:,3)+B_ext_tmp(3)
          if (headtt) print*,'calc_pencils_magnetic: B_ext=',B_ext
          if (headtt) print*,'calc_pencils_magnetic: B_ext_tmp=',B_ext_tmp
        endif
!  add the external potential field
        if (lB_ext_pot) then
          call get_global(bb_ext_pot,m,n,'B_ext_pot')
          p%bb=p%bb+bb_ext_pot
        endif
!  add external B-field (currently for spheromak experiments)
        if (lbb_ext) then
          call get_global(bb_ext,m,n,'bb_ext')
          p%bb=p%bb+bb_ext
        endif
      endif
! ab
      if (lpencil(i_ab)) call dot_mn(p%aa,p%bb,p%ab)
! uxb
      if (lpencil(i_uxb)) then
        call cross_mn(p%uu,p%bb,p%uxb)
        if (lee_ext) then
          call get_global(ee_ext,m,n,'ee_ext')
          p%uxB=p%uxb+ee_ext
        endif
      endif
! b2
      if (lpencil(i_b2)) call dot2_mn(p%bb,p%b2)
!ajwm should prob combine these next two
! gradcurla
      if (lpencil(i_gradcurla)) &
          call del2v_etc(f,iaa,gradcurl=p%gradcurla)
! bij, del2a, graddiva
      if (lpencil(i_bij) .or. lpencil(i_del2a) .or. lpencil(i_graddiva)) &
          call bij_etc(f,iaa,p%bij,p%del2a,p%graddiva)
! jj
      if (lpencil(i_jj)) then
        call curl_mn(p%bij,p%jj,p%bb)
        p%jj=mu01*p%jj
        if (ljj_ext) then
!  external current (currently for spheromak experiments)
          call get_global(ee_ext,m,n,'ee_ext')
          !call get_global(jj_ext,m,n,'jj_ext')
          !jj=jj+jj_ext
          p%jj=p%jj-ee_ext*displacement_gun
        endif
      endif
!  in spherical geometry, del2a is best written as graddiva-jj.
      if (lpencil(i_del2a)) then
        if (lspherical) p%del2a=p%graddiva-p%jj
      endif
! j2
      if (lpencil(i_j2)) call dot2_mn(p%jj,p%j2)
! jb
      if (lpencil(i_jb)) call dot_mn(p%jj,p%bb,p%jb)
! va2
      if (lpencil(i_va2)) p%va2=p%b2*mu01*p%rho1
! jxb
      if (lpencil(i_jxb)) call cross_mn(p%jj,p%bb,p%jxb)
! jxbr
      if (lpencil(i_jxbr)) then
        rho1_jxb=p%rho1
!  set rhomin_jxb>0 in order to limit the jxb term at very low densities.
!  set va2max_jxb>0 in order to limit the jxb term at very high alven speeds.
!  set va2power_jxb to an integer value in order to specify the power
!  of the limiting term,
        if (rhomin_jxb>0) rho1_jxb=min(rho1_jxb,1/rhomin_jxb)
        if (va2max_jxb>0) rho1_jxb=rho1_jxb/(1+(p%va2/va2max_jxb)**va2power_jxb)
        call multsv_mn(rho1_jxb,p%jxb,p%jxbr)
      endif
! ub
      if (lpencil(i_ub)) call dot_mn(p%uu,p%bb,p%ub)
! uxb2
      if (lpencil(i_uxb2)) call dot2_mn(p%uxb,p%uxb2)
! uxj
      if (lpencil(i_uxj)) call cross_mn(p%uu,p%jj,p%uxj)
! beta
      if (lpencil(i_beta)) p%beta=0.5*p%b2/p%pp
! djuidjbi
      if (lpencil(i_djuidjbi)) call multmm_sc(p%uij,p%bij,p%djuidjbi)
! jo
      if (lpencil(i_jo)) call dot(p%jj,p%oo,p%jo)
! ujxb
      if (lpencil(i_ujxb)) call dot_mn(p%uu,p%jxb,p%ujxb)
! oxu
      if (lpencil(i_oxu)) call cross_mn(p%oo,p%uu,p%oxu)
! oxuxb
      if (lpencil(i_oxuxb)) call cross_mn(p%oxu,p%bb,p%oxuxb)
! jxbxb
      if (lpencil(i_jxbxb)) call cross_mn(p%jxb,p%bb,p%jxbxb)
! jxbrxb
      if (lpencil(i_jxbrxb)) call cross_mn(p%jxbr,p%bb,p%jxbrxb)
! glnrhoxb
      if (lpencil(i_glnrhoxb)) call cross_mn(p%glnrho,p%bb,p%glnrhoxb)
! del4a
      if (lpencil(i_del4a)) call del4v(f,iaa,p%del4a)
! del6a
      if (lpencil(i_del6a)) call del6v(f,iaa,p%del6a)
! oxj        
      if (lpencil(i_oxj)) call cross_mn(p%oo,p%jj,p%oxJ)
! jij
      if (lpencil(i_jij)) then
        do j=1,3
          do i=1,3
            p%jij(:,i,j)=.5*(p%bij(:,i,j)+p%bij(:,j,i))
          enddo
        enddo
      endif
! sj
      if (lpencil(i_sj)) call multmm_sc(p%sij,p%jij,p%sj)
! ss12
      if (lpencil(i_ss12)) p%ss12=sqrt(abs(p%sj))
!
! mf_EMF
! needed if a mean field (mf) model is calculated
!
      if (lpencil(i_mf_EMF)) then
!
!  possibility of dynamical alpha
!
        if (lalpm) then
          alpha_total=alpha_effect+f(l1:l2,m,n,ialpm)
        else
          alpha_total=alpha_effect
        endif
!
!  possibility of conventional alpha quenching (rescales alpha_total)
!  initialize EMF with alpha_total*bb
!
        if (alpha_quenching/=0.) alpha_total=alpha_total/(1.+alpha_quenching*p%b2)
        call multsv_mn(alpha_total,p%bb,p%mf_EMF)
!
!  add possible delta x J effect and turbulent diffusion to EMF
!
        if (delta_effect/=0.) p%mf_EMF=p%mf_EMF+delta_effect*p%oxJ
        if (meanfield_etat/=0.) p%mf_EMF=p%mf_EMF-meanfield_etat*p%jj
      endif
      if (lpencil(i_mf_EMFdotB)) call dot_mn(p%mf_EMF,p%bb,p%mf_EMFdotB)
!
    endsubroutine calc_pencils_magnetic
!***********************************************************************
    subroutine daa_dt(f,df,p)
!
!  magnetic field evolution
!
!  calculate dA/dt=uxB+3/2 Omega_0 A_y x_dir -eta mu_0 J
!  for mean field calculations one can also add dA/dt=...+alpha*bb+delta*WXJ
!  add jxb/rho to momentum equation
!  add eta mu_0 j2/rho to entropy equation
!
!  22-nov-01/nils: coded
!   1-may-02/wolf: adapted for pencil_modular
!  17-jun-03/ulf:  added bx^2, by^2 and bz^2 as separate diagnostics
!   8-aug-03/axel: introduced B_ext21=1./B_ext**2, and set =1 to avoid div. by 0
!  12-aug-03/christer: added alpha effect (alpha in the equation above)
!  26-may-04/axel: ambipolar diffusion added
!  18-jun-04/axel: Hall term added
!
      use Cdata
      use Sub
      use Slices
      use Global, only: get_global
      use IO, only: output_pencil
      use Special, only: special_calc_magnetic
      use Mpicomm, only: stop_it
      use EquationOfState, only: eoscalc,gamma1
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
!      
      real, dimension (nx,3) :: geta,uxDxuxb,fres,meanfield_EMF
      real, dimension (nx) :: uxb_dotB0,oxuxb_dotB0,jxbxb_dotB0,uxDxuxb_dotB0
      real, dimension (nx) :: gpxb_dotB0,uxj_dotB0,hall_ueff2
      real, dimension (nx) :: b2b13,sign_jo
      real, dimension (nx) :: eta_mn,eta_tot
      real, dimension (nx) :: eta_smag,etatotal,fres2
      real :: tmp,eta_out1
      integer :: i,j
!
      intent(in)     :: f
      intent(inout)  :: df     
!
!  identify module and boundary conditions
!
      if (headtt.or.ldebug) print*,'daa_dt: SOLVE'
      if (headtt) then
        call identify_bcs('Ax',iax)
        call identify_bcs('Ay',iay)
        call identify_bcs('Az',iaz)
      endif
!
!  add jxb/rho to momentum equation
!
      if (lhydro) then
        if (llorentzforce) df(l1:l2,m,n,iux:iuz)=df(l1:l2,m,n,iux:iuz)+p%jxbr
      endif
!
!  add eta mu_0 j2/rho to entropy equation
!
      if (lentropy) then
        df(l1:l2,m,n,iss)=df(l1:l2,m,n,iss)+(eta*mu0)*p%j2*p%rho1*p%TT1
      endif
!
!  calculate restive term
!
      select case (iresistivity)

      case ('eta-const')
        fres=eta*p%del2a
        etatotal=eta
      case ('hyper3')
        fres=eta*p%del6a
        etatotal=eta
      case ('hyper2')
        fres=eta*p%del4a
        etatotal=eta  
      case ('shell')
        call eta_shell(eta_mn,geta)
        do j=1,3; fres(:,j)=eta_mn*p%del2a(:,j)+geta(:,j)*p%diva; enddo
        etatotal=eta_mn
      case ('shock')
        if (eta_shock/=0) then
          eta_tot=eta+eta_shock*p%shock
          geta=eta_shock*p%gshock
          do j=1,3; fres(:,j)=eta_tot*p%del2a(:,j)+geta(:,j)*p%diva; enddo
          etatotal=eta+eta_shock*p%shock
        else
          fres=eta*p%del2a
          etatotal=eta
        endif
      case ('Smagorinsky')
        eta_smag=(D_smag*dxmax)**2.*sqrt(p%j2)
        call multsv(eta_smag+eta,p%del2a,fres)
        etatotal=eta_smag+eta
      case ('Smagorinsky_cross')        
        sign_jo=1.
        do i=1,nx 
          if (p%jo(i) .lt. 0) sign_jo(i)=-1.
        enddo
        eta_smag=(D_smag*dxmax)**2.*sign_jo*sqrt(p%jo*sign_jo)
        call multsv(eta_smag+eta,p%del2a,fres)
        etatotal=eta_smag+eta
      case default
        if (lroot) print*,'daa_dt: no such ires:',iresistivity
        call stop_it("")
      end select
      if (headtt) print*,'daa_dt: iresistivity=',iresistivity
!
!  Switch off diffusion of horizontal components in boundary slice if
!  requested by boundconds
!
      if (lfrozen_bz_z_bot) then
!
!  Only need to do this for nonperiodic z direction, on bottommost
!  processor and in bottommost pencils
!
        if ((.not. lperi(3)) .and. (ipz == 0) .and. (n == n1)) then
          fres(:,1) = 0.
          fres(:,2) = 0.
        endif
      endif
!
!  Induction equation
!
      df(l1:l2,m,n,iax:iaz) = df(l1:l2,m,n,iax:iaz) + p%uxb + fres
!
!  Ambipolar diffusion in the strong coupling approximation
!
      if (nu_ni/=0.) then
        df(l1:l2,m,n,iax:iaz)=df(l1:l2,m,n,iax:iaz)+nu_ni1*p%jxbrxb
        etatotal=etatotal+nu_ni1*p%va2
      endif
!
!  Hall term
!
      if (hall_term/=0.) then
        if (headtt) print*,'daa_dt: hall_term=',hall_term
        df(l1:l2,m,n,iax:iaz)=df(l1:l2,m,n,iax:iaz)-hall_term*p%jxb
        if (lfirst.and.ldt) then
          advec_hall=abs(p%uu(:,1)-hall_term*p%jj(:,1))*dx_1(l1:l2)+ &
                     abs(p%uu(:,2)-hall_term*p%jj(:,2))*dy_1(  m  )+ &
                     abs(p%uu(:,3)-hall_term*p%jj(:,3))*dz_1(  n  )
        endif
        if (headtt.or.ldebug) print*,'duu_dt: max(advec_hall) =',&
                                     maxval(advec_hall)
      endif
!
!  Alpha effect
!  additional terms if Mean Field Theory is included
!
      if (lmeanfield_theory.and.(alpha_effect/=0..or.delta_effect/=0.)) then
        df(l1:l2,m,n,iax:iaz)=df(l1:l2,m,n,iax:iaz)+p%mf_EMF
        if (lOmega_effect) call Omega_effect(f,df)
      endif
!
!  Possibility of adding extra diffusivity in some halo of given geometry:
!  Note that eta_out is total eta in halo (not eta_out+eta)
!
      if (height_eta/=0.) then
        if (headtt) print*,'daa_dt: height_eta,eta_out=',height_eta,eta_out
        tmp=(z(n)/height_eta)**2
        eta_out1=eta_out*(1.-exp(-tmp**5/max(1.-tmp,1e-5)))-eta
        df(l1:l2,m,n,iax:iaz)=df(l1:l2,m,n,iax:iaz)-(eta_out1*mu0)*p%jj
      endif
!
!  possibility of relaxation of A in exterior region
!
      if (tau_aa_exterior/=0.) call calc_tau_aa_exterior(f,df)
!
!  ``va^2/dx^2'' and ``eta/dx^2'' for timestep
!  in the diffusive timestep, we include possible contribution from
!  meanfield_etat, which is however only invoked in mean field models
!
      if (lfirst.and.ldt) then
        advec_va2=((p%bb(:,1)*dx_1(l1:l2))**2+ &
                   (p%bb(:,2)*dy_1(  m  ))**2+ &
                   (p%bb(:,3)*dz_1(  n  ))**2)*mu01*p%rho1
        diffus_eta=(etatotal+meanfield_etat)*dxyz_2
        if (ldiagnos.and.idiag_dteta/=0) then
          call max_mn_name(diffus_eta/cdtv,idiag_dteta,l_dt=.true.)
        endif
      endif
      if (headtt.or.ldebug) then
        print*,'duu_dt: max(advec_va2) =',maxval(advec_va2)
        print*,'duu_dt: max(diffus_eta) =',maxval(diffus_eta)
      endif
!
!  Special contributions to this module are called here
!
      if (lspecial) call special_calc_magnetic(f,df,p%uu,p%rho1,p%TT1,p%uij)
!
!  phi-averages
!  Note that this does not necessarily happen with ldiagnos=.true.
!
      if (l2davgfirst) then
        call phisum_mn_name_rz(p%bb(:,1)*pomx+p%bb(:,2)*pomy,idiag_brmphi)
        call phisum_mn_name_rz(p%bb(:,1)*phix+p%bb(:,2)*phiy,idiag_bpmphi)
        call phisum_mn_name_rz(p%bb(:,3),idiag_bzmphi)
        call phisum_mn_name_rz(p%b2,idiag_b2mphi)
        if (idiag_jbmphi/=0) call phisum_mn_name_rz(p%jb,idiag_jbmphi)
        if (any((/idiag_uxbrmphi,idiag_uxbpmphi,idiag_uxbzmphi/) /= 0)) then
          call phisum_mn_name_rz(p%uxb(:,1)*pomx+p%uxb(:,2)*pomy,idiag_uxbrmphi)
          call phisum_mn_name_rz(p%uxb(:,1)*phix+p%uxb(:,2)*phiy,idiag_uxbpmphi)
          call phisum_mn_name_rz(p%uxb(:,3)                     ,idiag_uxbzmphi)
        endif
      endif
!
!  Calculate diagnostic quantities
!
      if (ldiagnos) then

        if (idiag_beta1m/=0) call sum_mn_name(p%beta,idiag_beta1m)
        if (idiag_beta1max/=0) call max_mn_name(p%beta,idiag_beta1max)

        if (idiag_b2m/=0) call sum_mn_name(p%b2,idiag_b2m)
        if (idiag_bm2/=0) call max_mn_name(p%b2,idiag_bm2)
        if (idiag_brms/=0) call sum_mn_name(p%b2,idiag_brms,lsqrt=.true.)
        if (idiag_bmax/=0) call max_mn_name(p%b2,idiag_bmax,lsqrt=.true.)
        if (idiag_aybym2/=0) &
            call sum_mn_name(2*p%aa(:,2)*p%bb(:,2),idiag_aybym2)
        if (idiag_abm/=0) call sum_mn_name(p%ab,idiag_abm)
        if (idiag_ubm/=0) call sum_mn_name(p%ub,idiag_ubm)
        if (idiag_bx2m/=0) call sum_mn_name(p%bb(:,1)*p%bb(:,1),idiag_bx2m)
        if (idiag_by2m/=0) call sum_mn_name(p%bb(:,2)*p%bb(:,2),idiag_by2m)
        if (idiag_bz2m/=0) call sum_mn_name(p%bb(:,3)*p%bb(:,3),idiag_bz2m)
        if (idiag_bxbym/=0) call sum_mn_name(p%bb(:,1)*p%bb(:,2),idiag_bxbym)
        if (idiag_bxbzm/=0) call sum_mn_name(p%bb(:,1)*p%bb(:,3),idiag_bxbzm)
        if (idiag_bybzm/=0) call sum_mn_name(p%bb(:,2)*p%bb(:,3),idiag_bybzm)

        if (idiag_djuidjbim/=0) call sum_mn_name(p%djuidjbi,idiag_djuidjbim)
!
!  this doesn't need to be as frequent (check later)
!
        if (idiag_bxmz/=0) call xysum_mn_name_z(p%bb(:,1),idiag_bxmz)
        if (idiag_bymz/=0) call xysum_mn_name_z(p%bb(:,2),idiag_bymz)
        if (idiag_bzmz/=0) call xysum_mn_name_z(p%bb(:,3),idiag_bzmz)
        if (idiag_bxmxy/=0) call zsum_mn_name_xy(p%bb(:,1),idiag_bxmxy)
        if (idiag_bymxy/=0) call zsum_mn_name_xy(p%bb(:,2),idiag_bymxy)
        if (idiag_bzmxy/=0) call zsum_mn_name_xy(p%bb(:,3),idiag_bzmxy)
        if (idiag_bxmxz/=0) call ysum_mn_name_xz(p%bb(:,1),idiag_bxmxz)
        if (idiag_bymxz/=0) call ysum_mn_name_xz(p%bb(:,2),idiag_bymxz)
        if (idiag_bzmxz/=0) call ysum_mn_name_xz(p%bb(:,3),idiag_bzmxz)
!
!  magnetic field components at one point (=pt)
!
        if (lroot.and.m==mpoint.and.n==npoint) then
          if (idiag_bxpt/=0) call save_name(p%bb(lpoint-nghost,1),idiag_bxpt)
          if (idiag_bypt/=0) call save_name(p%bb(lpoint-nghost,2),idiag_bypt)
          if (idiag_bzpt/=0) call save_name(p%bb(lpoint-nghost,3),idiag_bzpt)
        endif
!
!  v_A = |B|/sqrt(rho); in units where "4pi"=1
!
        if (idiag_vArms/=0) call sum_mn_name(p%va2,idiag_vArms,lsqrt=.true.)
        if (idiag_vAmax/=0) call max_mn_name(p%va2,idiag_vAmax,lsqrt=.true.)
        if (idiag_dtb/=0) &
            call max_mn_name(sqrt(advec_va2)/cdt,idiag_dtb,l_dt=.true.)
!
! <J.B>
!
        if (idiag_jbm/=0) call sum_mn_name(p%jb,idiag_jbm)
        if (idiag_j2m/=0) call sum_mn_name(p%j2,idiag_j2m)
        if (idiag_jm2/=0) call max_mn_name(p%j2,idiag_jm2)
        if (idiag_jrms/=0) call sum_mn_name(p%j2,idiag_jrms,lsqrt=.true.)
        if (idiag_jmax/=0) call max_mn_name(p%j2,idiag_jmax,lsqrt=.true.)
        if (idiag_epsM_LES/=0) call sum_mn_name(eta_smag*p%j2,idiag_epsM_LES)
!
!  Not correct for hyperresistivity:
!
        if (idiag_epsM/=0) call sum_mn_name(eta*p%j2,idiag_epsM)
!
! <A^2> and A^2|max
!
        if (idiag_arms/=0) call sum_mn_name(p%a2,idiag_arms,lsqrt=.true.)
        if (idiag_amax/=0) call max_mn_name(p%a2,idiag_amax,lsqrt=.true.)
!
!  calculate surface integral <2ExA>*dS
!
        if (idiag_exaym2/=0) call helflux(p%aa,p%uxb,p%jj)
!
!  calculate surface integral <2ExJ>*dS
!
        if (idiag_exjm2/=0) call curflux(p%uxb,p%jj)
!
!  calculate emf for alpha effect (for imposed field)
!  Note that uxbm means <EMF.B0>/B0^2, so it gives already alpha=EMF/B0.
!
        if (idiag_uxbm/=0 .or. idiag_uxbmx/=0 .or. idiag_uxbmy/=0 &
            .or. idiag_uxbmz/=0) then
          uxb_dotB0=B_ext(1)*p%uxb(:,1)+B_ext(2)*p%uxb(:,2)+B_ext(3)*p%uxb(:,3)
          uxb_dotB0=uxb_dotB0*B_ext21
          if (idiag_uxbm/=0) call sum_mn_name(uxb_dotB0,idiag_uxbm)
          if (idiag_uxbmx/=0) call sum_mn_name(p%uxb(:,1),idiag_uxbmx)
          if (idiag_uxbmy/=0) call sum_mn_name(p%uxb(:,2),idiag_uxbmy)
          if (idiag_uxbmz/=0) call sum_mn_name(p%uxb(:,3),idiag_uxbmz)
        endif
!
!  calculate <uxj>.B0/B0^2
!
        if (idiag_uxjm/=0) then
          uxj_dotB0=B_ext(1)*p%uxj(:,1)+B_ext(2)*p%uxj(:,2)+B_ext(3)*p%uxj(:,3)
          uxj_dotB0=uxj_dotB0*B_ext21
          call sum_mn_name(uxj_dotB0,idiag_uxjm)
        endif
!
!  calculate <u x B>_rms, <resistive terms>_rms, <ratio ~ Rm>_rms
!
        if (idiag_uxBrms/=0) call sum_mn_name(p%uxb2,idiag_uxBrms,lsqrt=.true.)
        if (idiag_Bresrms/=0 .or. idiag_Rmrms/=0) then
          call dot2_mn(fres,fres2)
          if (idiag_Bresrms/=0) &
              call sum_mn_name(fres2,idiag_Bresrms,lsqrt=.true.)
          if (idiag_Rmrms/=0) &
              call sum_mn_name(p%uxb2/fres2,idiag_Rmrms,lsqrt=.true.)
        endif
!
!  calculate <u.(jxb)>
!
        if (idiag_ujxbm/=0) call sum_mn_name(p%ujxb,idiag_ujxbm)
!
!  magnetic triple correlation term (for imposed field)
!
        if (idiag_jxbxbm/=0) then
          jxbxb_dotB0=B_ext(1)*p%jxbxb(:,1)+B_ext(2)*p%jxbxb(:,2)+B_ext(3)*p%jxbxb(:,3)
          jxbxb_dotB0=jxbxb_dotB0*B_ext21
          call sum_mn_name(jxbxb_dotB0,idiag_jxbxbm)
        endif
!
!  triple correlation from Reynolds tensor (for imposed field)
!
        if (idiag_oxuxbm/=0) then
          oxuxb_dotB0=B_ext(1)*p%oxuxb(:,1)+B_ext(2)*p%oxuxb(:,2)+B_ext(3)*p%oxuxb(:,3)
          oxuxb_dotB0=oxuxb_dotB0*B_ext21
          call sum_mn_name(oxuxb_dotB0,idiag_oxuxbm)
        endif
!
!  triple correlation from pressure gradient (for imposed field)
!  (assume cs2=1, and that no entropy evolution is included)
        !
        if (idiag_gpxbm/=0) then
          gpxb_dotB0=B_ext(1)*p%glnrhoxb(:,1)+B_ext(2)*p%glnrhoxb(:,2)+B_ext(3)*p%glnrhoxb(:,3)
          gpxb_dotB0=gpxb_dotB0*B_ext21
          call sum_mn_name(oxuxb_dotB0,idiag_gpxbm)
        endif
!
!  < u x curl(uxB) > = < E_i u_{j,j} - E_j u_{j,i} >
!   ( < E_1 u2,2 + E1 u3,3 - E2 u2,1 - E3 u3,1 >
!     < E_2 u1,1 + E2 u3,3 - E1 u2,1 - E3 u3,2 >
!     < E_3 u1,1 + E3 u2,2 - E1 u3,1 - E2 u2,3 > )
!
        if (idiag_uxDxuxbm/=0) then
          uxDxuxb(:,1)=p%uxb(:,1)*(p%uij(:,2,2)+p%uij(:,3,3))-p%uxb(:,2)*p%uij(:,2,1)-p%uxb(:,3)*p%uij(:,3,1)
          uxDxuxb(:,2)=p%uxb(:,2)*(p%uij(:,1,1)+p%uij(:,3,3))-p%uxb(:,1)*p%uij(:,1,2)-p%uxb(:,3)*p%uij(:,3,2)
          uxDxuxb(:,3)=p%uxb(:,3)*(p%uij(:,1,1)+p%uij(:,2,2))-p%uxb(:,1)*p%uij(:,1,3)-p%uxb(:,2)*p%uij(:,2,3)
          uxDxuxb_dotB0=B_ext(1)*uxDxuxb(:,1)+B_ext(2)*uxDxuxb(:,2)+B_ext(3)*uxDxuxb(:,3)
          uxDxuxb_dotB0=uxDxuxb_dotB0*B_ext21
          call sum_mn_name(uxDxuxb_dotB0,idiag_uxDxuxbm)
        endif
!
!  < b2 b1,3 >
!
        if (idiag_b2b13m/=0) then
          b2b13=p%bb(:,2)*p%bij(:,1,3)
          call sum_mn_name(b2b13,idiag_b2b13m)
        endif
!
      endif ! endif (ldiagnos)
!
!  debug output
!
      if (headtt .and. lfirst .and. ip<=4) then
        call output_pencil(trim(directory)//'/aa.dat',p%aa,3)
        call output_pencil(trim(directory)//'/bb.dat',p%bb,3)
        call output_pencil(trim(directory)//'/jj.dat',p%jj,3)
        call output_pencil(trim(directory)//'/del2A.dat',p%del2a,3)
        call output_pencil(trim(directory)//'/JxBr.dat',p%jxbr,3)
        call output_pencil(trim(directory)//'/JxB.dat',p%jxb,3)
        call output_pencil(trim(directory)//'/df.dat',df(l1:l2,m,n,:),mvar)
      endif
!
!  write B-slices for output in wvid in run.f90
!  Note: ix is the index with respect to array with ghost zones.
!
      if (lvid.and.lfirst) then
        do j=1,3
          bb_yz(m-m1+1,n-n1+1,j)=p%bb(ix-l1+1,j)
          if (m==iy)  bb_xz(:,n-n1+1,j)=p%bb(:,j)
          if (n==iz)  bb_xy(:,m-m1+1,j)=p%bb(:,j)
          if (n==iz2) bb_xy2(:,m-m1+1,j)=p%bb(:,j)
        enddo
        b2_yz(m-m1+1,n-n1+1)=p%b2(ix-l1+1)
        if (m==iy)  b2_xz(:,n-n1+1)=p%b2
        if (n==iz)  b2_xy(:,m-m1+1)=p%b2
        if (n==iz2) b2_xy2(:,m-m1+1)=p%b2
        jb_yz(m-m1+1,n-n1+1)=p%jb(ix-l1+1)
        if (m==iy)  jb_xz(:,n-n1+1)=p%jb
        if (n==iz)  jb_xy(:,m-m1+1)=p%jb
        if (n==iz2) jb_xy2(:,m-m1+1)=p%jb
        if (bthresh_per_brms/=0) call calc_bthresh
        call vecout(41,trim(directory)//'/bvec',p%bb,bthresh,nbvec)
      endif
!
    endsubroutine daa_dt
!***********************************************************************
    subroutine eta_shell(eta_mn,geta)
!
!   24-nov-03/dave: coded 
!
      use Cdata
      use Sub, only: step, der_step
!
      real, dimension (nx) :: eta_mn
      real, dimension (nx) :: prof,eta_r
      real, dimension (nx,3) :: geta
      real :: d_int=0.,d_ext=0.
!
      eta_r=0.
!
      if (eta_int > 0.) d_int=eta_int-eta
      if (eta_ext > 0.) d_ext=eta_ext-eta
!
!     calculate steps in resistivity
!
      prof=step(r_mn,r_int,wresistivity)
      eta_mn=d_int*(1-prof)
      prof=step(r_mn,r_ext,wresistivity)
      eta_mn=eta+eta_mn+d_ext*prof
!
!     calculate radial derivative of steps and gradient of eta
!
      prof=der_step(r_mn,r_int,wresistivity)
      eta_r=-d_int*prof
      prof=der_step(r_mn,r_ext,wresistivity)
      eta_r=eta_r+d_ext*prof
      geta=evr*spread(eta_r,2,3)
!
    endsubroutine eta_shell
!***********************************************************************
    subroutine calc_bthresh()
!
!  calculate bthresh from brms, give warnings if there are problems
!
!   6-aug-03/axel: coded
!
      use Cdata
!
!  give warning if brms is not set in prints.in
!
      if (idiag_brms==0) then
        if (lroot.and.lfirstpoint) then
          print*,'calc_bthresh: need to set brms in print.in to get bthresh'
        endif
      endif
!
!  if nvec exceeds nbvecmax (=1/4) of points per processor, then begin to
!  increase scaling factor on bthresh. These settings will stay in place
!  until the next restart
!
      if (nbvec>nbvecmax.and.lfirstpoint) then
        print*,'calc_bthresh: processor ',iproc,': bthresh_scl,nbvec,nbvecmax=', &
                                                   bthresh_scl,nbvec,nbvecmax
        bthresh_scl=bthresh_scl*1.2
      endif
!
!  calculate bthresh as a certain fraction of brms
!
      bthresh=bthresh_scl*bthresh_per_brms*brms
!
    endsubroutine calc_bthresh
!***********************************************************************
    subroutine rescaling(f)
!
!  This routine could be turned into a wrapper routine later on,
!  if we want to do dynamic rescaling also on other quantities.
!
!  22-feb-05/axel: coded
!
      use Cdata
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real :: scl
      integer :: j
!
      intent(inout) :: f
!
!  do rescaling only if brms is finite.
!  Note: we rely here on the brms that is update every it1 timesteps.
!  This may not always be sufficient.
!
      if (brms/=0) then
        scl=1.+rescaling_fraction*(brms_target/brms-1.)
        if (headtt) print*,'rescaling: scl=',scl
        do j=iax,iaz
          do n=n1,n2
            f(l1:l2,m1:m2,n,j)=scl*f(l1:l2,m1:m2,n,j)
          enddo
        enddo
      endif
!
    endsubroutine rescaling
!***********************************************************************
    subroutine calc_tau_aa_exterior(f,df)
!
!  magnetic field relaxation to zero on time scale tau_aa_exterior within
!  exterior region. For the time being this means z > zgrav.
!
!  29-jul-02/axel: coded
!
      use Cdata
      use Gravity
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      real :: scl
      integer :: j
!
      intent(in) :: f
      intent(out) :: df
!
      if (headtt) print*,'calc_tau_aa_exterior: tau=',tau_aa_exterior
      if (z(n)>zgrav) then
        scl=1./tau_aa_exterior
        do j=iax,iaz
          df(l1:l2,m,n,j)=df(l1:l2,m,n,j)-scl*f(l1:l2,m,n,j)
        enddo
      endif
!
    endsubroutine calc_tau_aa_exterior
!***********************************************************************
    subroutine Omega_effect(f,df)
!
!  Omega effect coded (normally used in context of mean field theory)
!  Can do uniform shear (0,Sx,0), and the cosx*cosz profile (solar CZ).
!
!  30-apr-05/axel: coded
!
      use Cdata
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
!
      intent(in) :: f
      intent(inout) :: df
!
!  use gauge transformation, uxB = -Ay*grad(Uy) + gradient-term
!
      select case(Omega_profile)
      case('nothing'); print*,'Omega_profile=nothing'
      case('(0,Sx,0)')
        if (headtt) print*,'Omega_effect: uniform shear, S=',Omega_ampl
        df(l1:l2,m,n,iax)=df(l1:l2,m,n,iax)-Omega_ampl*f(l1:l2,m,n,iay)
      case('(0,cosx*cosz,0)')
        if (headtt) print*,'Omega_effect: solar shear, S=',Omega_ampl
        df(l1:l2,m,n,iax)=df(l1:l2,m,n,iax)+Omega_ampl*f(l1:l2,m,n,iay) &
            *sin(x(l1:l2))*cos(z(n))
        df(l1:l2,m,n,iaz)=df(l1:l2,m,n,iaz)+Omega_ampl*f(l1:l2,m,n,iay) &
            *cos(x(l1:l2))*sin(z(n))
      case default; print*,'Omega_profile=unknown'
      endselect
!
    endsubroutine Omega_effect
!***********************************************************************
    subroutine helflux(aa,uxb,jj)
!
!  magnetic helicity flux (preliminary)
!
!  14-aug-03/axel: coded
!
      use Cdata
      use Sub
!
      real, dimension (nx,3), intent(in) :: aa,uxb,jj
      real, dimension (nx,3) :: ee
      real, dimension (nx) :: FHx,FHz
      real :: FH
!
      ee=eta*jj-uxb
!
!  calculate magnetic helicity flux in the X and Z directions
!
      FHx=-2*ee(:,3)*aa(:,2)*dsurfyz
      FHz=+2*ee(:,1)*aa(:,2)*dsurfxy
!
!  sum up contribution per pencil
!  and then stuff result into surf_mn_name for summing up all processors.
!
      FH=FHx(nx)-FHx(1)
      if (ipz==0       .and.n==n1) FH=FH-sum(FHz)
      if (ipz==nprocz-1.and.n==n2) FH=FH+sum(FHz)
      call surf_mn_name(FH,idiag_exaym2)
!
    endsubroutine helflux
!***********************************************************************
    subroutine curflux(uxb,jj)
!
!  current helicity flux (preliminary)
!
!  27-nov-03/axel: adapted from helflux
!
      use Cdata
      use Sub
!
      real, dimension (nx,3), intent(in) :: uxb,jj
      real, dimension (nx,3) :: ee
      real, dimension (nx) :: FCx,FCz
      real :: FC
!
      ee=eta*jj-uxb
!
!  calculate current helicity flux in the X and Z directions
!  Could speed up by only calculating here boundary points!
!
      FCx=2*(ee(:,2)*jj(:,3)-ee(:,3)*jj(:,2))*dsurfyz
      FCz=2*(ee(:,1)*jj(:,2)-ee(:,2)*jj(:,1))*dsurfxy
!
!  sum up contribution per pencil
!  and then stuff result into surf_mn_name for summing up all processors.
!
      FC=FCx(nx)-FCx(1)
      if (ipz==0       .and.n==n1) FC=FC-sum(FCz)
      if (ipz==nprocz-1.and.n==n2) FC=FC+sum(FCz)
      call surf_mn_name(FC,idiag_exjm2)
!
    endsubroutine curflux
!***********************************************************************
    subroutine read_magnetic_init_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat
!
      if (present(iostat)) then
        read(unit,NML=magnetic_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=magnetic_init_pars,ERR=99)
      endif
!
99    return
    endsubroutine read_magnetic_init_pars
!***********************************************************************
    subroutine write_magnetic_init_pars(unit)
      integer, intent(in) :: unit
!
      write(unit,NML=magnetic_init_pars)
!
    endsubroutine write_magnetic_init_pars
!***********************************************************************
    subroutine read_magnetic_run_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat
!
      if (present(iostat)) then
        read(unit,NML=magnetic_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=magnetic_run_pars,ERR=99)
      endif
!
99    return
    endsubroutine read_magnetic_run_pars
!***********************************************************************
    subroutine write_magnetic_run_pars(unit)
      integer, intent(in) :: unit
!
      write(unit,NML=magnetic_run_pars)
!
    endsubroutine write_magnetic_run_pars
!***********************************************************************
    subroutine rprint_magnetic(lreset,lwrite)
!
!  reads and registers print parameters relevant for magnetic fields
!
!   3-may-02/axel: coded
!  27-may-02/axel: added possibility to reset list
!
      use Cdata
      use Sub
!
      integer :: iname,inamez,ixy,ixz,irz
      logical :: lreset,lwr
      logical, optional :: lwrite
!
      lwr = .false.
      if (present(lwrite)) lwr=lwrite
!
!  reset everything in case of RELOAD
!  (this needs to be consistent with what is defined above!)
!
      if (lreset) then
        idiag_b2m=0; idiag_bm2=0; idiag_j2m=0; idiag_jm2=0; idiag_abm=0
        idiag_jbm=0; idiag_ubm=0; idiag_epsM=0
        idiag_bxpt=0; idiag_bypt=0; idiag_bzpt=0; idiag_epsM_LES=0
        idiag_aybym2=0; idiag_exaym2=0; idiag_exjm2=0
        idiag_brms=0; idiag_bmax=0; idiag_jrms=0; idiag_jmax=0; idiag_vArms=0
        idiag_vAmax=0; idiag_dtb=0; idiag_arms=0; idiag_amax=0
        idiag_beta1m=0; idiag_beta1max=0; idiag_bx2m=0
        idiag_by2m=0; idiag_bz2m=0
        idiag_bxbym=0; idiag_bxbzm=0; idiag_bybzm=0; idiag_djuidjbim=0
        idiag_bxmz=0; idiag_bymz=0; idiag_bzmz=0; idiag_bmx=0; idiag_bmy=0
        idiag_bmz=0; idiag_bxmxy=0; idiag_bymxy=0; idiag_bzmxy=0
        idiag_uxbm=0; idiag_oxuxbm=0; idiag_jxbxbm=0.; idiag_gpxbm=0.
        idiag_uxDxuxbm=0.; idiag_uxbmx=0; idiag_uxbmy=0; idiag_uxbmz=0
        idiag_uxjm=0; idiag_ujxbm=0; idiag_b2b13m=0
        idiag_brmphi=0; idiag_bpmphi=0; idiag_bzmphi=0; idiag_b2mphi=0
        idiag_jbmphi=0; idiag_uxbrmphi=0; idiag_uxbpmphi=0; idiag_uxbzmphi=0;
        idiag_dteta=0; idiag_uxBrms=0; idiag_Bresrms=0; idiag_Rmrms=0
!merge_axel
!       i_b2m=0; i_bm2=0; i_j2m=0; i_jm2=0; i_abm=0; i_jbm=0; i_ubm=0; i_epsM=0
!       i_bxpt=0; i_bypt=0; i_bzpt=0; i_epsM_LES=0
!       i_aybym2=0; i_exaym2=0; i_exjm2=0
!       i_brms=0; i_bmax=0; i_jrms=0; i_jmax=0; i_vArms=0; i_vAmax=0; i_dtb=0
!       i_beta1m=0; i_beta1max=0
!       i_bx2m=0; i_by2m=0; i_bz2m=0
!       i_bxbym=0; i_bxbzm=0; i_bybzm=0; i_djuidjbim=0
!       i_bxmz=0; i_bymz=0; i_bzmz=0; i_bmx=0; i_bmy=0; i_bmz=0
!       i_bxmxy=0; i_bymxy=0; i_bzmxy=0
!       i_bxmxz=0; i_bymxz=0; i_bzmxz=0
!       i_uxbm=0; i_oxuxbm=0; i_jxbxbm=0.; i_gpxbm=0.; i_uxDxuxbm=0.
!       i_uxbmx=0; i_uxbmy=0; i_uxbmz=0
!       i_uxjm=0; i_ujxbm=0
!       i_b2b13m=0
!       i_brmphi=0; i_bpmphi=0; i_bzmphi=0; i_b2mphi=0; i_jbmphi=0
!       i_uxbrmphi=0; i_uxbpmphi=0; i_uxbzmphi=0;
!       i_dteta=0
      endif
!
!  check for those quantities that we want to evaluate online
!
      do iname=1,nname
        call parse_name(iname,cname(iname),cform(iname),'dteta',idiag_dteta)
        call parse_name(iname,cname(iname),cform(iname),'aybym2',idiag_aybym2)
        call parse_name(iname,cname(iname),cform(iname),'exaym2',idiag_exaym2)
        call parse_name(iname,cname(iname),cform(iname),'exjm2',idiag_exjm2)
        call parse_name(iname,cname(iname),cform(iname),'abm',idiag_abm)
        call parse_name(iname,cname(iname),cform(iname),'jbm',idiag_jbm)
        call parse_name(iname,cname(iname),cform(iname),'ubm',idiag_ubm)
        call parse_name(iname,cname(iname),cform(iname),'b2m',idiag_b2m)
        call parse_name(iname,cname(iname),cform(iname),'bm2',idiag_bm2)
        call parse_name(iname,cname(iname),cform(iname),'j2m',idiag_j2m)
        call parse_name(iname,cname(iname),cform(iname),'jm2',idiag_jm2)
        call parse_name(iname,cname(iname),cform(iname),'epsM',idiag_epsM)
        call parse_name(iname,cname(iname),cform(iname),&
            'epsM_LES',idiag_epsM_LES)
        call parse_name(iname,cname(iname),cform(iname),'brms',idiag_brms)
        call parse_name(iname,cname(iname),cform(iname),'bmax',idiag_bmax)
        call parse_name(iname,cname(iname),cform(iname),'jrms',idiag_jrms)
        call parse_name(iname,cname(iname),cform(iname),'jmax',idiag_jmax)
        call parse_name(iname,cname(iname),cform(iname),'arms',idiag_arms)
        call parse_name(iname,cname(iname),cform(iname),'amax',idiag_amax)
        call parse_name(iname,cname(iname),cform(iname),'vArms',idiag_vArms)
        call parse_name(iname,cname(iname),cform(iname),'vAmax',idiag_vAmax)
        call parse_name(iname,cname(iname),cform(iname),&
            'beta1m',idiag_beta1m)
        call parse_name(iname,cname(iname),cform(iname),&
            'beta1max',idiag_beta1max)
        call parse_name(iname,cname(iname),cform(iname),'dtb',idiag_dtb)
        call parse_name(iname,cname(iname),cform(iname),'bx2m',idiag_bx2m)
        call parse_name(iname,cname(iname),cform(iname),'by2m',idiag_by2m)
        call parse_name(iname,cname(iname),cform(iname),'bz2m',idiag_bz2m)
        call parse_name(iname,cname(iname),cform(iname),'bxbym',idiag_bxbym)
        call parse_name(iname,cname(iname),cform(iname),'bxbzm',idiag_bxbzm)
        call parse_name(iname,cname(iname),cform(iname),'bybzm',idiag_bybzm)
        call parse_name(iname,cname(iname),cform(iname),&
            'djuidjbim',idiag_djuidjbim)
        call parse_name(iname,cname(iname),cform(iname),'uxbm',idiag_uxbm)
        call parse_name(iname,cname(iname),cform(iname),'uxbmx',idiag_uxbmx)
        call parse_name(iname,cname(iname),cform(iname),'uxbmy',idiag_uxbmy)
        call parse_name(iname,cname(iname),cform(iname),'uxbmz',idiag_uxbmz)
        call parse_name(iname,cname(iname),cform(iname),'uxjm',idiag_uxjm)
        call parse_name(iname,cname(iname),cform(iname),'ujxbm',idiag_ujxbm)
        call parse_name(iname,cname(iname),cform(iname),'jxbxbm',idiag_jxbxbm)
        call parse_name(iname,cname(iname),cform(iname),'oxuxbm',idiag_oxuxbm)
        call parse_name(iname,cname(iname),cform(iname),'gpxbm',idiag_gpxbm)
        call parse_name(iname,cname(iname),cform(iname),&
            'uxDxuxbm',idiag_uxDxuxbm)
        call parse_name(iname,cname(iname),cform(iname),'b2b13m',idiag_b2b13m)
        call parse_name(iname,cname(iname),cform(iname),'bmx',idiag_bmx)
        call parse_name(iname,cname(iname),cform(iname),'bmy',idiag_bmy)
        call parse_name(iname,cname(iname),cform(iname),'bmz',idiag_bmz)
        call parse_name(iname,cname(iname),cform(iname),'bxpt',idiag_bxpt)
        call parse_name(iname,cname(iname),cform(iname),'bypt',idiag_bypt)
        call parse_name(iname,cname(iname),cform(iname),'bzpt',idiag_bzpt)
        call parse_name(iname,cname(iname),cform(iname),'uxBrms',idiag_uxBrms)
        call parse_name(iname,cname(iname),cform(iname),'Bresrms',idiag_Bresrms)
        call parse_name(iname,cname(iname),cform(iname),'Rmrms',idiag_Rmrms)
      enddo
!
!  check for those quantities for which we want xy-averages
!
      do inamez=1,nnamez
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'bxmz',idiag_bxmz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'bymz',idiag_bymz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'bzmz',idiag_bzmz)
      enddo
!
!  check for those quantities for which we want y-averages
!
      do ixz=1,nnamexz
        call parse_name(ixz,cnamexz(ixz),cformxz(ixz),'bxmxz',idiag_bxmxz)
        call parse_name(ixz,cnamexz(ixz),cformxz(ixz),'bymxz',idiag_bymxz)
        call parse_name(ixz,cnamexz(ixz),cformxz(ixz),'bzmxz',idiag_bzmxz)
      enddo
!
!  check for those quantities for which we want z-averages
!
      do ixy=1,nnamexy
        call parse_name(ixy,cnamexy(ixy),cformxy(ixy),'bxmxy',idiag_bxmxy)
        call parse_name(ixy,cnamexy(ixy),cformxy(ixy),'bymxy',idiag_bymxy)
        call parse_name(ixy,cnamexy(ixy),cformxy(ixy),'bzmxy',idiag_bzmxy)
      enddo
!
!  check for those quantities for which we want phi-averages
!
      do irz=1,nnamerz
        call parse_name(irz,cnamerz(irz),cformrz(irz),'brmphi'  ,idiag_brmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'bpmphi'  ,idiag_bpmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'bzmphi'  ,idiag_bzmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'b2mphi'  ,idiag_b2mphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'jbmphi'  ,idiag_jbmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'uxbrmphi',idiag_uxbrmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'uxbpmphi',idiag_uxbpmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'uxbzmphi',idiag_uxbzmphi)
      enddo
!
!  write column, idiag_XYZ, where our variable XYZ is stored
!
      if (lwr) then
        write(3,*) 'i_dteta=',idiag_dteta
        write(3,*) 'i_aybym2=',idiag_aybym2
        write(3,*) 'i_exaym2=',idiag_exaym2
        write(3,*) 'i_exjm2=',idiag_exjm2
        write(3,*) 'i_abm=',idiag_abm
        write(3,*) 'i_jbm=',idiag_jbm
        write(3,*) 'i_ubm=',idiag_ubm
        write(3,*) 'i_b2m=',idiag_b2m
        write(3,*) 'i_bm2=',idiag_bm2
        write(3,*) 'i_j2m=',idiag_j2m
        write(3,*) 'i_jm2=',idiag_jm2
        write(3,*) 'i_epsM=',idiag_epsM
        write(3,*) 'i_epsM_LES=',idiag_epsM_LES
        write(3,*) 'i_brms=',idiag_brms
        write(3,*) 'i_bmax=',idiag_bmax
        write(3,*) 'i_jrms=',idiag_jrms
        write(3,*) 'i_jmax=',idiag_jmax
        write(3,*) 'i_arms=',idiag_arms
        write(3,*) 'i_amax=',idiag_amax
        write(3,*) 'i_vArms=',idiag_vArms
        write(3,*) 'i_vAmax=',idiag_vAmax
        write(3,*) 'i_beta1m=',idiag_beta1m
        write(3,*) 'i_beta1max=',idiag_beta1max
        write(3,*) 'i_dtb=',idiag_dtb
        write(3,*) 'i_bx2m=',idiag_bx2m
        write(3,*) 'i_by2m=',idiag_by2m
        write(3,*) 'i_bz2m=',idiag_bz2m
        write(3,*) 'i_bxbym=',idiag_bxbym
        write(3,*) 'i_bxbzm=',idiag_bxbzm
        write(3,*) 'i_bybzm=',idiag_bybzm
        write(3,*) 'i_djuidjbim=',idiag_djuidjbim
        write(3,*) 'i_uxbm=',idiag_uxbm
        write(3,*) 'i_uxbmx=',idiag_uxbmx
        write(3,*) 'i_uxbmy=',idiag_uxbmy
        write(3,*) 'i_uxbmz=',idiag_uxbmz
        write(3,*) 'i_uxjm=',idiag_uxjm
        write(3,*) 'i_ujxbm=',idiag_ujxbm
        write(3,*) 'i_oxuxbm=',idiag_oxuxbm
        write(3,*) 'i_jxbxbm=',idiag_jxbxbm
        write(3,*) 'i_gpxbm=',idiag_gpxbm
        write(3,*) 'i_uxDxuxbm=',idiag_uxDxuxbm
        write(3,*) 'i_b2b13m=',idiag_b2b13m
        write(3,*) 'i_bxmz=',idiag_bxmz
        write(3,*) 'i_bymz=',idiag_bymz
        write(3,*) 'i_bzmz=',idiag_bzmz
        write(3,*) 'i_bmx=',idiag_bmx
        write(3,*) 'i_bmy=',idiag_bmy
        write(3,*) 'i_bmz=',idiag_bmz
        write(3,*) 'i_bxpt=',idiag_bxpt
        write(3,*) 'i_bypt=',idiag_bypt
        write(3,*) 'i_bzpt=',idiag_bzpt
        write(3,*) 'i_bxmxy=',idiag_bxmxy
        write(3,*) 'i_bymxy=',idiag_bymxy
        write(3,*) 'i_bzmxy=',idiag_bzmxy
        write(3,*) 'i_bxmxz=',idiag_bxmxz
        write(3,*) 'i_bymxz=',idiag_bymxz
        write(3,*) 'i_bzmxz=',idiag_bzmxz
        write(3,*) 'i_brmphi=',idiag_brmphi
        write(3,*) 'i_bpmphi=',idiag_bpmphi
        write(3,*) 'i_bzmphi=',idiag_bzmphi
        write(3,*) 'i_b2mphi=',idiag_b2mphi
        write(3,*) 'i_jbmphi=',idiag_jbmphi
        write(3,*) 'i_uxBrms=',idiag_uxBrms
        write(3,*) 'i_Bresrms=',idiag_Bresrms
        write(3,*) 'i_Rmrms=',idiag_Rmrms
        write(3,*) 'nname=',nname
        write(3,*) 'nnamexy=',nnamexy
        write(3,*) 'nnamexz=',nnamexz
        write(3,*) 'nnamez=',nnamez
        write(3,*) 'iaa=',iaa
        write(3,*) 'iax=',iax
        write(3,*) 'iay=',iay
        write(3,*) 'iaz=',iaz
      endif
!
    endsubroutine rprint_magnetic
!***********************************************************************
    subroutine calc_mfield
!
!  calculate mean magnetic field from xy- or z-averages
!
!  19-jun-02/axel: moved from print to here
!   9-nov-02/axel: corrected bxmy(m,j); it used bzmy instead!
!
      use Cdata
      use Sub
!
      logical,save :: first=.true.
      real, dimension(nx) :: bymx,bzmx
      real, dimension(ny,nprocy) :: bxmy,bzmy
      real :: bmx,bmy,bmz
      integer :: l,j
!
!  Magnetic energy in vertically averaged field
!  The bymxy and bzmxy must have been calculated,
!  so they are present on the root processor.
!
        if (idiag_bmx/=0) then
          if (idiag_bymxy==0.or.idiag_bzmxy==0) then
            if (first) print*,"calc_mfield:                  WARNING"
            if (first) print*, &
                    "calc_mfield: NOTE: to get bmx, bymxy and bzmxy must also be set in zaver"
            if (first) print*, &
                    "calc_mfield:       We proceed, but you'll get bmx=0"
            bmx=0.
          else
            do l=1,nx
              bymx(l)=sum(fnamexy(l,:,:,idiag_bymxy))/(ny*nprocy)
              bzmx(l)=sum(fnamexy(l,:,:,idiag_bzmxy))/(ny*nprocy)
            enddo
            bmx=sqrt(sum(bymx**2+bzmx**2)/nx)
          endif
          call save_name(bmx,idiag_bmx)
        endif
!
!  similarly for bmy
!
        if (idiag_bmy/=0) then
          if (idiag_bxmxy==0.or.idiag_bzmxy==0) then
            if (first) print*,"calc_mfield:                  WARNING"
            if (first) print*, &
                    "calc_mfield: NOTE: to get bmy, bxmxy and bzmxy must also be set in zaver"
            if (first) print*, &
                    "calc_mfield:       We proceed, but you'll get bmy=0"
            bmy=0.
          else
            do j=1,nprocy
            do m=1,ny
              bxmy(m,j)=sum(fnamexy(:,m,j,idiag_bxmxy))/nx
              bzmy(m,j)=sum(fnamexy(:,m,j,idiag_bzmxy))/nx
            enddo
            enddo
            bmy=sqrt(sum(bxmy**2+bzmy**2)/(ny*nprocy))
          endif
          call save_name(bmy,idiag_bmy)
        endif
!
!  Magnetic energy in horizontally averaged field
!  The bxmz and bymz must have been calculated,
!  so they are present on the root processor.
!
        if (idiag_bmz/=0) then
          if (idiag_bxmz==0.or.idiag_bymz==0) then
            if (first) print*,"calc_mfield:                  WARNING"
            if (first) print*, &
                    "calc_mfield: NOTE: to get bmz, bxmz and bymz must also be set in xyaver"
            if (first) print*, &
                    "calc_mfield:       This may be because we renamed zaver.in into xyaver.in"
            if (first) print*, &
                    "calc_mfield:       We proceed, but you'll get bmz=0"
            bmz=0.
          else
            bmz=sqrt(sum(fnamez(:,:,idiag_bxmz)**2+fnamez(:,:,idiag_bymz)**2)/(nz*nprocz))
          endif
          call save_name(bmz,idiag_bmz)
        endif
!
      first = .false.
    endsubroutine calc_mfield
!***********************************************************************
    subroutine alfven_x(ampl,f,iuu,iaa,ilnrho,xx,kx)
!
!  Alfven wave propagating in the z-direction
!  ux = cos(kz-ot), for B0z=1 and rho=1.
!  Ay = sin(kz-ot), ie Bx=-cos(kz-ot)
!
!  satisfies the equations
!  dlnrho/dt = -ux'
!  dux/dt = -cs2*(lnrho)'
!  duy/dt = B0*By'  ==>  dux/dt = B0*Ay''
!  dBy/dt = B0*uy'  ==>  dAy/dt = -B0*ux
!
!   8-nov-03/axel: coded
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: xx
      real :: ampl,kx
      integer :: iuu,iaa,ilnrho
!
!  ux and Ay.
!  Don't overwrite the density, just add to the log of it.
!
      f(:,:,:,ilnrho)=ampl*sin(kx*xx)+f(:,:,:,ilnrho)
      f(:,:,:,iuu+0)=+ampl*sin(kx*xx)
      f(:,:,:,iuu+1)=+ampl*sin(kx*xx)
      f(:,:,:,iaa+2)=-ampl*cos(kx*xx)
!
    endsubroutine alfven_x
!***********************************************************************
    subroutine alfven_z(ampl,f,iuu,iaa,zz,kz,mu0)
!
!  Alfven wave propagating in the z-direction
!  ux = cos(kz-ot), for B0z=1 and rho=1.
!  Ay = sin(kz-ot), ie Bx=-cos(kz-ot)
!
!  satisfies the equations
!  dux/dt = Bx'  ==>  dux/dt = -Ay''
!  dBx/dt = ux'  ==>  dAy/dt = -ux.
!
!  18-aug-02/axel: coded
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: zz
      real :: ampl,kz,mu0
      integer :: iuu,iaa
!
!  ux and Ay
!
      f(:,:,:,iuu+0)=+ampl*cos(kz*zz)
      f(:,:,:,iaa+1)=+ampl*sin(kz*zz)*sqrt(mu0)
!
    endsubroutine alfven_z
!***********************************************************************
    subroutine alfvenz_rot(ampl,f,iuu,iaa,zz,kz,O)
!
!  Alfven wave propagating in the z-direction (with Coriolis force)
!  ux = cos(kz-ot), for B0z=1 and rho=1.
!  Ay = sin(kz-ot), ie Bx=-cos(kz-ot)
!
!  satisfies the equations
!  dux/dt - 2Omega*uy = -Ay''
!  duy/dt + 2Omega*ux = +Ax''
!  dAx/dt = +uy
!  dAy/dt = -ux
!
!  18-aug-02/axel: coded
!
      use Cdata, only: lroot
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: zz
      real :: ampl,kz,O,fac
      integer :: iuu,iaa
!
!  ux, uy, Ax and Ay
!
      if (lroot) print*,'alfvenz_rot: Alfven wave with rotation; O,kz=',O,kz
      fac=-O+sqrt(O**2+kz**2)
      f(:,:,:,iuu+0)=-ampl*sin(kz*zz)*fac/kz
      f(:,:,:,iuu+1)=-ampl*cos(kz*zz)*fac/kz
      f(:,:,:,iaa+0)=+ampl*sin(kz*zz)/kz
      f(:,:,:,iaa+1)=+ampl*cos(kz*zz)/kz
!
    endsubroutine alfvenz_rot
!***********************************************************************
    subroutine alfvenz_rot_shear(ampl,f,iuu,iaa,zz,kz,O)
!
!  Alfven wave propagating in the z-direction (with Coriolis force and shear)
!
!  satisfies the equations
!  dux/dt - 2*Omega*uy = -Ay''
!  duy/dt + 1/2*Omega*ux = +Ax''
!  dAx/dt = 3/2*Omega*Ay + uy
!  dAy/dt = -ux
!
!  Assume B0=rho0=mu0=1
!
!  28-june-04/anders: coded
!
      use Cdata, only: lroot
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: zz
      real :: ampl,kz,O
      complex :: fac
      integer :: iuu,iaa
!
!  ux, uy, Ax and Ay
!
      if (lroot) print*,'alfvenz_rot_shear: '// &
          'Alfven wave with rotation and shear; O,kz=',O,kz
      fac=cmplx(O-sqrt(16*kz**2+O**2),0.)
      f(:,:,:,iuu+0)=f(:,:,:,iuu+0) + ampl*fac/(4*kz)*sin(kz*zz)
      f(:,:,:,iuu+1)=f(:,:,:,iuu+1) + ampl*real(exp(cmplx(0,zz*kz))* &
          fac*sqrt(2*kz**2+O*fac)/(sqrt(2.)*kz*(-6*O-fac)))
      f(:,:,:,iaa+0)=ampl*sin(kz*zz)/kz
      f(:,:,:,iaa+1)=-ampl*2*sqrt(2.)*aimag(exp(cmplx(0,zz*kz))* &
          sqrt(2*kz**2+O*fac)/(-6*O-fac)/(cmplx(0,kz)))
!
    endsubroutine alfvenz_rot_shear
!***********************************************************************
    subroutine fluxrings(f,ivar,xx,yy,zz,profile)
!
!  Magnetic flux rings. Constructed from a canonical ring which is the
!  rotated and translated:
!    AA(xxx) = D*AA0(D^(-1)*(xxx-xxx_disp)) ,
!  where AA0(xxx) is the canonical ring and D the rotation matrix
!  corresponding to a rotation by phi around z, followed by a
!  rotation by theta around y.
!  The array was already initialized to zero before calling this
!  routine.
!  Optional argument `profile' allows to choose a different profile (see
!  norm_ring())
!
      use Cdata
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,3)    :: tmpv
      real, dimension (mx,my,mz)      :: xx,yy,zz,xx1,yy1,zz1
      real, dimension(3) :: axis,disp
      real    :: phi,theta,ct,st,cp,sp
      real    :: fring,Iring,R0,width
      integer :: i,ivar
      character (len=*), optional :: profile
      character (len=labellen) :: prof
!
      if (present(profile)) then
        prof = profile
      else
        prof = 'tanh'
      endif

      if (any((/fring1,fring2,Iring1,Iring2/) /= 0.)) then
        ! fringX is the magnetic flux, IringX the current
        if (lroot) then
          print*, 'fluxrings: Initialising magnetic flux rings'
        endif
        do i=1,2
          if (i==1) then
            fring = fring1      ! magnetic flux along ring
            Iring = Iring1      ! current along ring (for twisted flux tube)
            R0    = Rring1      ! radius of ring
            width = wr1         ! ring thickness
            axis  = axisr1 ! orientation
            disp  = dispr1    ! position
          else
            fring = fring2
            Iring = Iring2
            R0    = Rring2
            width = wr2
            axis  = axisr2
            disp  = dispr2
          endif
          phi   = atan2(axis(2),axis(1)+epsi)
          theta = atan2(sqrt(axis(1)**2+axis(2)**2)+epsi,axis(3))
          ct = cos(theta); st = sin(theta)
          cp = cos(phi)  ; sp = sin(phi)
          ! Calculate D^(-1)*(xxx-disp)
          xx1 =  ct*cp*(xx-disp(1)) + ct*sp*(yy-disp(2)) - st*(zz-disp(3))
          yy1 = -   sp*(xx-disp(1)) +    cp*(yy-disp(2))
          zz1 =  st*cp*(xx-disp(1)) + st*sp*(yy-disp(2)) + ct*(zz-disp(3))
          call norm_ring(xx1,yy1,zz1,fring,Iring,R0,width,tmpv,PROFILE=prof)
          ! calculate D*tmpv
          f(:,:,:,ivar  ) = f(:,:,:,ivar  ) + amplaa*( &
               + ct*cp*tmpv(:,:,:,1) - sp*tmpv(:,:,:,2) + st*cp*tmpv(:,:,:,3))
          f(:,:,:,ivar+1) = f(:,:,:,ivar+1) + amplaa*( &
               + ct*sp*tmpv(:,:,:,1) + cp*tmpv(:,:,:,2) + st*sp*tmpv(:,:,:,3))
          f(:,:,:,ivar+2) = f(:,:,:,ivar+2) + amplaa*( &
               - st   *tmpv(:,:,:,1)                    + ct   *tmpv(:,:,:,3))
        enddo
      endif
      if (lroot) print*, 'fluxrings: Magnetic flux rings initialized'
!
    endsubroutine fluxrings
!***********************************************************************
    subroutine norm_ring(xx,yy,zz,fring,Iring,R0,width,vv,profile)
!
!  Generate vector potential for a flux ring of magnetic flux FRING,
!  current Iring (not correctly normalized), radius R0 and thickness
!  WIDTH in normal orientation (lying in the x-y plane, centred at (0,0,0)).
!
!   1-may-02/wolf: coded
!
      use Cdata, only: mx,my,mz
      use Mpicomm, only: stop_it
!
      real, dimension (mx,my,mz,3) :: vv
      real, dimension (mx,my,mz)   :: xx,yy,zz,phi,tmp
      real :: fring,Iring,R0,width
      character (len=*) :: profile
!
      vv = 0.
!
!  magnetic ring
!
      tmp = sqrt(xx**2+yy**2)-R0

      select case(profile)

      case('tanh')
        vv(:,:,:,3) = - fring * 0.5*(1+tanh(tmp/width)) &
                              * 0.5/width/cosh(zz/width)**2

      case default
        call stop_it('norm_ring: No such fluxtube profile')
      endselect
!
!  current ring (to twist the B-lines)
!
!      tmp = tmp**2 + zz**2 + width**2  ! need periodic analog of this
      tmp = width - sqrt(tmp**2 + zz**2)
      tmp = Iring*0.5*(1+tanh(tmp/width))     ! Now the A_phi component
      phi = atan2(yy,xx)
      vv(:,:,:,1) = - tmp*sin(phi)
      vv(:,:,:,2) =   tmp*cos(phi)
!
    endsubroutine norm_ring
!***********************************************************************
    subroutine force_free_jet(mu,xx,yy,zz)
!
!  Force free magnetic field configuration for jet simulations
!  with a fixed accretion disk at the bottom boundary.
!
!  The input parameter mu specifies the radial dependency of
!  the magnetic field in the disk.
!
!  Solves the laplace equation in cylindrical coordinates for the
!  phi-component of the vector potential. A_r and A_z are taken to
!  be zero.
!
!    nabla**2 A_phi - A_phi / r**2 = 0
!
!  For the desired boundary condition in the accretion disk
!
!    B_r=B0*r**(mu-1)  (z == 0)
!
!  the solution is
!
!    A_phi = Hypergeometric2F1( (1-mu)/2, (2+mu)/2, 2, xi**2 )
!            *xi*(r**2+z**2)**(mu/2)
!
!  where xi = sqrt(r**2/(r**2+z**2))
!
!
!  30-may-04/tobi: coded
!
      use Cdata, only: x,y,z,lroot,directory,ip,m,n,pi,r_ref
      use Sub, only: hypergeometric2F1,gamma_function
      use Global, only: set_global
      use Deriv, only: der
      use IO, only: output

      real, intent(in) :: mu
      real, dimension(mx,my,mz), intent(in) :: xx,yy,zz
      real :: xi2,A_phi
      real :: r2
      real :: B1r_,B1z_,B1
      real, parameter :: tol=10*epsilon(1.0)
      integer :: l
      real, dimension(mx,my,mz) :: Ax_ext,Ay_ext
      real, dimension(nx,3) :: bb_ext_pot
      real, dimension(nx) :: bb_x,bb_y,bb_z
!
!  calculate un-normalized |B| at r=r_ref and z=0 for later normalization
!
      if (lroot.and.ip<=5) print*,'FORCE_FREE_JET: calculating normalization'

      B1r_=sin(pi*mu/2)*gamma_function(   abs(mu) /2) / &
                        gamma_function((1+abs(mu))/2)

      B1z_=cos(pi*mu/2)*gamma_function((1+abs(mu))/2) / &
                        gamma_function((2+abs(mu))/2)

      B1=sqrt(4/pi)*r_ref**(mu-1)*sqrt(B1r_**2+B1z_**2)
!
!  calculate external vector potential
!
      if (lroot) print*,'FORCE_FREE_JET: calculating external vector potential'

      if (lforce_free_test) then

        if (lroot) print*,'FORCE_FREE_JET: using analytic solution for mu=-1'
        Ax_ext=-2*yy*(1-zz/sqrt(xx**2+yy**2+zz**2))/(xx**2+yy**2)/B1
        Ay_ext= 2*xx*(1-zz/sqrt(xx**2+yy**2+zz**2))/(xx**2+yy**2)/B1

      else

        do l=1,mx
        do m=1,my
        do n=1,mz

          r2=x(l)**2+y(m)**2
          xi2=r2/(r2+z(n)**2)
          A_phi=hypergeometric2F1((1-mu)/2,(2+mu)/2,2.0,xi2,tol) &
               *sqrt(xi2)*sqrt(r2+z(n)**2)**mu/B1

          Ax_ext(l,m,n)=-y(m)*A_phi/sqrt(r2)
          Ay_ext(l,m,n)= x(l)*A_phi/sqrt(r2)

        enddo
        enddo
        enddo

      endif

!
!  calculate external magnetic field
!
      if (lroot.and.ip<=5) &
        print*,'FORCE_FREE_JET: calculating the external magnetic field'

      do n=n1,n2
      do m=m1,m2
        call der(Ay_ext,bb_x,3)
        bb_ext_pot(:,1)=-bb_x
        call der(Ax_ext,bb_y,3)
        bb_ext_pot(:,2)= bb_y
        call der(Ay_ext,bb_z,1)
        bb_ext_pot(:,3)= bb_z
        call der(Ax_ext,bb_z,2)
        bb_ext_pot(:,3)=bb_ext_pot(:,3)-bb_z
        call set_global(bb_ext_pot,m,n,'B_ext_pot',nx)
      enddo
      enddo

      if (ip<=5) then
        call output(trim(directory)//'/Ax_ext.dat',Ax_ext,1)
        call output(trim(directory)//'/Ay_ext.dat',Ay_ext,1)
      endif

    endsubroutine force_free_jet
!***********************************************************************
    subroutine geo_benchmark_B(f)
!
!  30-june-04/grs: coded
!
      use Cdata
      use Sub, only: calc_unitvects_sphere
      use Mpicomm, only: stop_it
!
      real, dimension (mx,my,mz,mvar+maux), intent(inout) :: f     
      real, dimension(nx) :: theta_mn,ar,atheta,aphi
      real :: C_int,C_ext,A_int,A_ext

      do imn=1,ny*nz
        n=nn(imn)
        m=mm(imn)
        call calc_unitvects_sphere()
        theta_mn=acos(z_mn/r_mn)
        phi_mn=atan2(y_mn,x_mn)

! calculate ax,ay,az (via ar,atheta,aphi) inside shell (& leave zero outside shell)
          select case(initaa) 
            case('geo-benchmark-case1')
              if (lroot .and. imn==1) print*, 'geo_benchmark_B: geo-benchmark-case1'
              C_int=-( -1./63.*r_int**4 + 11./84.*r_int**3*r_ext             &
                     + 317./1050.*r_int**2*r_ext**2                         &
                     - 1./5.*r_int**2*r_ext**2*log(r_int) )
              C_ext=-( -1./63.*r_ext**9 + 11./84.*r_ext**8*r_int             &
                     + 317./1050.*r_ext**7*r_int**2                         &
                     - 1./5.*r_ext**7*r_int**2*log(r_ext) )
              A_int=5./2.*(r_ext-r_int)
              A_ext=5./8.*(r_ext**4-r_int**4)

              where (r_mn < r_int)
                ar=C_int*ampl_B0*80.*2.*(3.*sin(theta_mn)**2-2.)*r_mn
                atheta=3.*C_int*ampl_B0*80.*sin(2.*theta_mn)*r_mn 
                aphi=ampl_B0*A_int*r_mn*sin(theta_mn)
              endwhere

              where (r_mn <= r_ext .and. r_mn >= r_int) 
                ar=ampl_B0*80.*2.*(3.*sin(theta_mn)**2-2.)*                 &
                   (   1./36.*r_mn**5 - 1./12.*(r_int+r_ext)*r_mn**4        &
                     + 1./14.*(r_int**2+4.*r_int*r_ext+r_ext**2)*r_mn**3    &
                     - 1./3.*(r_int**2*r_ext+r_int*r_ext**2)*r_mn**2        &
                     - 1./25.*r_int**2*r_ext**2*r_mn                        &
                     + 1./5.*r_int**2*r_ext**2*r_mn*log(r_mn) )
                atheta=-ampl_B0*80.*sin(2.*theta_mn)*                        &
                   (   7./36.*r_mn**5 - 1./2.*(r_int+r_ext)*r_mn**4         &
                     + 5./14.*(r_int**2+4.*r_int*r_ext+r_ext**2)*r_mn**3    &
                     - 4./3.*(r_int**2*r_ext+r_int*r_ext**2)*r_mn**2        &
                     + 2./25.*r_int**2*r_ext**2*r_mn                        &
                     + 3./5.*r_int**2*r_ext**2*r_mn*log(r_mn) )
                aphi=ampl_B0*5./8.*sin(theta_mn)*                           &
                   ( 4.*r_ext*r_mn - 3.*r_mn**2 - r_int**4/r_mn**2 ) 
              endwhere

              where (r_mn > r_ext)
                ar=C_ext*ampl_B0*80.*2.*(3.*sin(theta_mn)**2-2.)/r_mn**4
                atheta=-2.*C_ext*ampl_B0*80.*sin(2.*theta_mn)/r_mn**4
                aphi=ampl_B0*A_ext/r_mn**2*sin(theta_mn)
              endwhere
  
          ! debug checks -- look at a pencil near the centre...
          if (ip<=4 .and. imn==(ny+1)*nz/2) then
            print*,'r_int,r_ext',r_int,r_ext
            write(*,'(a45,2i6,2f15.7)') &
                 'geo_benchmark_B: minmax(r_mn), imn, iproc:', &
                 iproc, imn, minval(r_mn), maxval(r_mn)
            write(*,'(a45,2i6,2f15.7)') &
                 'geo_benchmark_B: minmax(theta_mn), imn, iproc:', &
                 iproc, imn, minval(theta_mn), maxval(theta_mn)
            write(*,'(a45,2i6,2f15.7)') &
                 'geo_benchmark_B: minmax(phi_mn), imn, iproc:', &
                 iproc, imn, minval(phi_mn), maxval(phi_mn)
            write(*,'(a45,2i6,2f15.7)') &
                 'geo_benchmark_B: minmax(ar), imn, iproc:', & 
                 iproc, imn, minval(ar), maxval(ar)
            write(*,'(a45,2i6,2f15.7)') &
                 'geo_benchmark_B: minmax(atheta), imn, iproc:', &
                 iproc, imn, minval(atheta), maxval(atheta)
            write(*,'(a45,2i6,2f15.7)') &
                 'geo_benchmark_B: minmax(aphi), imn, iproc:', &
                 iproc, imn, minval(aphi), maxval(aphi)
          endif

            case('geo-benchmark-case2')
              if (lroot .and. imn==1) print*, 'geo_benchmark_B: geo-benchmark-case2 not yet coded.'

            case default
              if (lroot .and. imn==1) print*,'geo_benchmark_B: case not defined!'
              call stop_it("")
          endselect

          f(l1:l2,m,n,iax)=sin(theta_mn)*cos(phi_mn)*ar + cos(theta_mn)*cos(phi_mn)*atheta - sin(phi_mn)*aphi
          f(l1:l2,m,n,iay)=sin(theta_mn)*sin(phi_mn)*ar + cos(theta_mn)*sin(phi_mn)*atheta + cos(phi_mn)*aphi
          f(l1:l2,m,n,iaz)=cos(theta_mn)*ar - sin(theta_mn)*atheta
      enddo

      if (ip<=14) then
        print*,'geo_benchmark_B: minmax(ax) on iproc:', iproc, minval(f(l1:l2,m1:m2,n1:n2,iax)),maxval(f(l1:l2,m1:m2,n1:n2,iax))
        print*,'geo_benchmark_B: minmax(ay) on iproc:', iproc, minval(f(l1:l2,m1:m2,n1:n2,iay)),maxval(f(l1:l2,m1:m2,n1:n2,iay))
        print*,'geo_benchmark_B: minmax(az) on iproc:', iproc, minval(f(l1:l2,m1:m2,n1:n2,iaz)),maxval(f(l1:l2,m1:m2,n1:n2,iaz))
      endif

    endsubroutine geo_benchmark_B
    
!***********************************************************************
    subroutine bc_frozen_in_bb_z(topbot)
!
!  Set flags to indicate that magnetic flux is frozen-in at the
!  z boundary. The implementation occurs in daa_dt where magnetic
!  diffusion is switched off in that layer.
!
      use Cdata
!
      character (len=3) :: topbot
!
      select case(topbot)
      case('bot')               ! bottom boundary
        lfrozen_bz_z_bot = .true.    ! set flag
      case('top')               ! top boundary
        lfrozen_bz_z_top = .true.    ! set flag
      case default
        print*, "bc_frozen_in_bb_z: ", topbot, " should be `top' or `bot'"
      endselect
!
    endsubroutine bc_frozen_in_bb_z
!***********************************************************************
      subroutine bc_aa_pot(f,topbot)
!
!  Potential field boundary condition for magnetic vector potential at
!  bottom or top boundary (in z).
!
!  14-jun-2002/axel: adapted from similar 
!   8-jul-2002/axel: introduced topbot argument
!
      use Cdata
      use Mpicomm, only: stop_it
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (nx,ny) :: f2,f3
      real, dimension (nx,ny,nghost+1) :: fz
      integer :: j
!
!  pontential field condition
!  check whether we want to do top or bottom (this is precessor dependent)
!
      select case(topbot)
!
!  pontential field condition at the bottom
!
      case('bot')
        if (headtt) print*,'bc_aa_pot: potential field boundary condition at the bottom'
        if (nprocy/=1) &
             call stop_it("bc_aa_pot: potential field doesn't work yet with nprocy/=1")
        do j=0,1
          f2=f(l1:l2,m1:m2,n1+1,iax+j)
          f3=f(l1:l2,m1:m2,n1+2,iax+j)
          call potential_field(fz,f2,f3,-1)
          f(l1:l2,m1:m2,1:n1,iax+j)=fz
        enddo
        !
        f2=f(l1:l2,m1:m2,n1,iax)
        f3=f(l1:l2,m1:m2,n1,iay)
        call potentdiv(fz,f2,f3,-1)
        f(l1:l2,m1:m2,1:n1,iaz)=-fz
!
!  pontential field condition at the top
!
      case('top')
        if (headtt) print*,'bc_aa_pot: potential field boundary condition at the top'
        if (nprocy/=1) &
             call stop_it("bc_aa_pot: potential field doesn't work yet with nprocy/=1")
        do j=0,1
          f2=f(l1:l2,m1:m2,n2-1,iax+j)
          f3=f(l1:l2,m1:m2,n2-2,iax+j)
          call potential_field(fz,f2,f3,+1)
          f(l1:l2,m1:m2,n2:mz,iax+j)=fz
        enddo
        !
        f2=f(l1:l2,m1:m2,n2,iax)
        f3=f(l1:l2,m1:m2,n2,iay)
        call potentdiv(fz,f2,f3,+1)
        f(l1:l2,m1:m2,n2:mz,iaz)=-fz
      case default
        if (lroot) print*,"bc_aa_pot: invalid argument"
      endselect
!
      endsubroutine bc_aa_pot
!***********************************************************************
      subroutine potential_field(fz,f2,f3,irev)
!
!  solves the potential field boundary condition;
!  fz is the boundary layer, and f2 and f3 are the next layers inwards.
!  The condition is the same on the two sides.
!
!  20-jan-00/axel+wolf: coded
!  22-mar-00/axel: corrected sign (it is the same on both sides)
!
     use Cdata
!
      real, dimension (nx,ny) :: fac,kk,f1r,f1i,g1r,g1i,f2,f2r,f2i,f3,f3r,f3i
      real, dimension (nx,ny,nghost+1) :: fz
      real, dimension (nx) :: kx
      real, dimension (ny) :: ky
      real :: delz
      integer :: i,irev
!
      f2r=f2; f2i=0
      f3r=f3; f3i=0
!
!  Transform
!
      call fft(f2r, f2i, nx*ny, nx,    nx,-1) ! x-direction
      call fft(f2r, f2i, nx*ny, ny, nx*ny,-1) ! y-direction
!
      call fft(f3r, f3i, nx*ny, nx,    nx,-1) ! x-direction
      call fft(f3r, f3i, nx*ny, ny, nx*ny,-1) ! y-direction
!
!  define wave vector
!
      kx=cshift((/(i-(nx-1)/2,i=0,nx-1)/),+(nx-1)/2)*2*pi/Lx
      ky=cshift((/(i-(ny-1)/2,i=0,ny-1)/),+(ny-1)/2)*2*pi/Ly
!
!  calculate 1/k^2, zero mean
!
      kk=sqrt(spread(kx**2,2,ny)+spread(ky**2,1,nx))
!
!  one-sided derivative
!
      fac=1./(3.+2.*dz*kk)
      f1r=fac*(4.*f2r-f3r)
      f1i=fac*(4.*f2i-f3i)
!
!  set ghost zones
!
      do i=0,nghost
        delz=i*dz
        fac=exp(-kk*delz)
        g1r=fac*f1r
        g1i=fac*f1i
!
!  Transform back
!
        call fft(g1r, g1i, nx*ny, nx,    nx,+1) ! x-direction
        call fft(g1r, g1i, nx*ny, ny, nx*ny,+1) ! y-direction
!
!  reverse order if irev=-1 (if we are at the bottom)
!
        if (irev==+1) fz(:,:,       i+1) = g1r/(nx*ny)  ! Renormalize
        if (irev==-1) fz(:,:,nghost-i+1) = g1r/(nx*ny)  ! Renormalize
      enddo
!
    endsubroutine potential_field
!***********************************************************************
      subroutine potentdiv(fz,f2,f3,irev)
!
!  solves the divA=0 for potential field boundary condition;
!  f2 and f3 correspond to Ax and Ay (input) and fz corresponds to Ax (out)
!  In principle we could save some ffts, by combining with the potential
!  subroutine above, but this is now easier
!
!  22-mar-02/axel: coded
!
     use Cdata
!
      real, dimension (nx,ny) :: fac,kk,kkkx,kkky,f1r,f1i,g1r,g1i,f2,f2r,f2i,f3,f3r,f3i
      real, dimension (nx,ny,nghost+1) :: fz
      real, dimension (nx) :: kx
      real, dimension (ny) :: ky
      real :: delz
      integer :: i,irev
!
      f2r=f2; f2i=0
      f3r=f3; f3i=0
!
!  Transform
!
      call fft(f2r, f2i, nx*ny, nx,    nx,-1) ! x-direction
      call fft(f2r, f2i, nx*ny, ny, nx*ny,-1) ! y-direction
!
      call fft(f3r, f3i, nx*ny, nx,    nx,-1) ! x-direction
      call fft(f3r, f3i, nx*ny, ny, nx*ny,-1) ! y-direction
!
!  define wave vector
!
      kx=cshift((/(i-nx/2,i=0,nx-1)/),+nx/2)
      ky=cshift((/(i-ny/2,i=0,ny-1)/),+ny/2)
!
!  calculate 1/k^2, zero mean
!
      kk=sqrt(spread(kx**2,2,ny)+spread(ky**2,1,nx))
      kkkx=spread(kx,2,ny)
      kkky=spread(ky,1,nx)
!
!  calculate 1/kk
!
      kk(1,1)=1.
      fac=1./kk
      fac(1,1)=0.
!
      f1r=fac*(-kkkx*f2i-kkky*f3i)
      f1i=fac*(+kkkx*f2r+kkky*f3r)
!
!  set ghost zones
!
      do i=0,nghost
        delz=i*dz
        fac=exp(-kk*delz)
        g1r=fac*f1r
        g1i=fac*f1i
!
!  Transform back
!
        call fft(g1r, g1i, nx*ny, nx,    nx,+1) ! x-direction
        call fft(g1r, g1i, nx*ny, ny, nx*ny,+1) ! y-direction
!
!  reverse order if irev=-1 (if we are at the bottom)
!
        if (irev==+1) fz(:,:,       i+1) = g1r/(nx*ny)  ! Renormalize
        if (irev==-1) fz(:,:,nghost-i+1) = g1r/(nx*ny)  ! Renormalize
      enddo
!
    endsubroutine potentdiv
!***********************************************************************

endmodule Magnetic
