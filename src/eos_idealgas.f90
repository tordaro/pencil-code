! $Id$
!
!  Equation of state for an ideal gas without ionization.
!
!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! CPARAM logical, parameter :: leos = .true.
!
! MVAR CONTRIBUTION 0
! MAUX CONTRIBUTION 0
!
! PENCILS PROVIDED ss; gss(3); ee; pp; lnTT; cs2; cp; cp1; cp1tilde
! PENCILS PROVIDED glnTT(3); TT; TT1; gTT(3); yH; hss(3,3); hlnTT(3,3)
! PENCILS PROVIDED del2ss; del6ss; del2lnTT; cv; cv1; del6lnTT; gamma
! PENCILS PROVIDED del2TT; del6TT; glnmumol(3); ppvap; csvap2
! PENCILS PROVIDED TTb; rho_anel; eth; geth(3); del2eth; heth(3,3)
! PENCILS PROVIDED eths; geths(3)
!
!***************************************************************
module EquationOfState
!
  use Cparam
  use Cdata
  use General, only: keep_compiler_quiet
  use Messages
!
  implicit none
!
  include 'eos.h'
!
  interface eoscalc ! Overload subroutine `eoscalc' function
    module procedure eoscalc_pencil   ! explicit f implicit m,n
    module procedure eoscalc_point    ! explicit lnrho, ss
    module procedure eoscalc_farray   ! explicit lnrho, ss
  end interface
!
  interface pressure_gradient ! Overload subroutine `pressure_gradient'
    module procedure pressure_gradient_farray  ! explicit f implicit m,n
    module procedure pressure_gradient_point   ! explicit lnrho, ss
  end interface
!
  integer, parameter :: ilnrho_ss=1, ilnrho_ee=2, ilnrho_pp=3
  integer, parameter :: ilnrho_lnTT=4, ilnrho_cs2=5
  integer, parameter :: irho_cs2=6, irho_ss=7, irho_lnTT=8, ilnrho_TT=9
  integer, parameter :: irho_TT=10, ipp_ss=11, ipp_cs2=12
  integer, parameter :: irho_eth=13, ilnrho_eth=14
  integer :: iglobal_cs2, iglobal_glnTT, ics
  real, dimension(mz) :: profz_eos=1.0,dprofz_eos=0.0
  real, dimension(3) :: beta_glnrho_global=0.0, beta_glnrho_scaled=0.0
  real :: lnTT0=impossible, TT0=impossible
  real :: xHe=0.0
  real :: mu=1.0
  real :: cs0=1.0, cs20=1.0, rho0=1., lnrho0=0., rho01=1.0, pp0=1.0
  real :: gamma=5.0/3.0
  real :: Rgas_cgs=0.0, Rgas, error_cp=1.0e-6
  real :: gamma_m1    !(=gamma-1)
  real :: gamma1   !(=1/gamma)
  real :: cp=impossible, cp1=impossible, cv=impossible, cv1=impossible
  real :: pres_corr=0.1
  real :: cs2top_ini=impossible, dcs2top_ini=impossible
  real :: cs2bot=impossible, cs2top=impossible
  real :: cs2cool=0.0
  real :: fac_cs=1.0
  real :: mpoly=impossible, mpoly0=1.5, mpoly1=1.5, mpoly2=1.5
  real :: width_eos_prof=0.2
  real :: sigmaSBt=1.0
  integer :: isothtop=0
  integer :: imass=1
  integer :: isothmid=0
  integer :: ieosvars=-1, ieosvar1=-1, ieosvar2=-1, ieosvar_count=0
  logical :: leos_isothermal=.false., leos_isentropic=.false.
  logical :: leos_isochoric=.false., leos_isobaric=.false.
  logical :: leos_localisothermal=.false.
  logical :: lanelastic_lin=.false., lcs_as_aux=.false., lcs_as_comaux=.false.
  character (len=labellen) :: ieos_profile='nothing'
!
  character (len=labellen) :: meanfield_Beq_profile
  real, pointer :: meanfield_Beq, chit_quenching, uturb
  real, dimension(:), pointer :: B_ext
!
  real, dimension(nchemspec,18):: species_constants
  real, dimension(nchemspec,7) :: tran_data
  real, dimension(nchemspec)   :: Lewis_coef, Lewis_coef1
!
!  Input parameters.
!
  namelist /eos_init_pars/ &
      xHe, mu, cp, cs0, rho0, gamma, error_cp, cs2top_ini, &
      dcs2top_ini, sigmaSBt, lanelastic_lin, lcs_as_aux, lcs_as_comaux,&
      fac_cs,isothmid,&
      lstratz, gztype, gz_coeff
!
!  Run parameters.
!
  namelist /eos_run_pars/ &
      xHe, mu, cp, cs0, rho0, gamma, error_cp, cs2top_ini,           &
      dcs2top_ini, ieos_profile, width_eos_prof,pres_corr, sigmaSBt, &
      lanelastic_lin, lcs_as_aux, lcs_as_comaux
!
!  Module variables
!
  real, dimension(mz) :: rho0z = 0.0, dlnrho0dz = 0.0
  real, dimension(mz) :: eth0z = 0.0
  logical :: lstratset = .false.
  integer, parameter :: BOT=1, TOP=nx
!
  contains
!***********************************************************************
    subroutine register_eos()
!
!  Register variables from the EquationOfState module.
!
!  14-jun-03/axel: adapted from register_eos
!
      leos_idealgas=.true.
!
      iyH=0
      ilnTT=0
!
      if ((ip<=8) .and. lroot) then
        print*, 'register_eos: ionization nvar = ', nvar
      endif
!
!  Identify version number.
!
      if (lroot) call svn_id( &
          '$Id$')
!
    endsubroutine register_eos
!***********************************************************************
    subroutine units_eos()
!
!  This routine calculates things related to units and must be called
!  before the rest of the units are being calculated.
!
!  22-jun-06/axel: adapted from initialize_eos
!   4-aug-09/axel: added possibility of vertical profile function
!
      use Mpicomm, only: stop_it
      use SharedVariables, only: put_shared_variable
      use Sub, only: erfunc
!
      real :: Rgas_unit_sys, cp_reference
      integer :: ierr
!
!  Set gamma_m1, cs20, and lnrho0, and rho01.
!  (used currently for non-dimensional equation of state)
!
      gamma_m1=gamma-1.0
      gamma1=1/gamma
      lnrho0=log(rho0)
      rho01 = 1./rho0
!
!  Avoid floating overflow if cs0 was not set.
!
      cs20=cs0**2
!
!  Initialize variable selection code (needed for RELOADing).
!
      ieosvars=-1
      ieosvar_count=0
!
!  Unless unit_temperature is set, calculate by default with cp=1.
!  If unit_temperature is set, cp must follow from this.
!  Conversely, if cp is set, then unit_temperature must follow from this.
!  If unit_temperature and cp are set, the problem is overdetermined,
!  but it may still be correct, so this will be checked here.
!  When gamma=1.0 (gamma_m1=0.0), write Rgas=mu*cp or cp=Rgas/mu.
!
      if (unit_system=='cgs') then
        Rgas_unit_sys=k_B_cgs/m_u_cgs
      elseif (unit_system=='SI') then
        Rgas_unit_sys=k_B_cgs/m_u_cgs*1.0e-4
      endif
!
      if (unit_temperature==impossible) then
        if (cp==impossible) cp=1.0
        if (gamma_m1==0.0) then
          Rgas=mu*cp
        else
          Rgas=mu*(1.0-gamma1)*cp
        endif
        unit_temperature=unit_velocity**2*Rgas/Rgas_unit_sys
      else
        Rgas=Rgas_unit_sys*unit_temperature/unit_velocity**2
        if (cp==impossible) then
          if (gamma_m1==0.0) then
            cp=Rgas/mu
          else
            cp=Rgas/(mu*gamma_m1*gamma1)
          endif
        else
!
!  Checking whether the units are overdetermined.
!  This is assumed to be the case when the two differ by error_cp.
!
          if (gamma_m1==0.0) then
            cp_reference=Rgas/mu
          else
            cp_reference=Rgas/(mu*gamma_m1*gamma1)
          endif
          if (abs(cp-cp_reference)/cp > error_cp) then
            if (lroot) print*,'initialize_eos: consistency: cp=', cp , &
                'while: cp_reference=', cp_reference
            call fatal_error('units_eos','cp is not correctly calculated')
          endif
        endif
      endif
      cp1=1/cp
      cv=gamma1*cp
      cv1=gamma*cp1
!
!  Need to calculate the equivalent of cs0.
!  Distinguish between gamma=1 case and not.
!
      if (gamma_m1/=0.0) then
        lnTT0=log(cs20/(cp*gamma_m1))  !(general case)
      else
        lnTT0=log(cs20/cp)  !(isothermal/polytropic cases: check!)
      endif
      pp0=Rgas*exp(lnTT0)*rho0
      TT0=exp(lnTT0)
!
! Shared variables
!
      call put_shared_variable('cs20',cs20,ierr)
      if (ierr/=0) call fatal_error('units_eos','problem when putting cs20')
!
      call put_shared_variable('mpoly',mpoly,ierr)
      if (ierr/=0) call fatal_error('units_eos','problem when putting mpoly')
!
      call put_shared_variable('gamma',gamma,ierr)
      if (ierr/=0) call fatal_error('units_eos','problem when putting gamma')
!
!  Check that everything is OK.
!
      if (lroot) then
        print*, 'initialize_eos: unit_temperature=', unit_temperature
        print*, 'initialize_eos: cp, lnTT0, cs0, pp0=', cp, lnTT0, cs0, pp0
      endif
!
!  Calculate profile functions (used as prefactors to turn off pressure
!  gradient term).
!
      if (ieos_profile=='nothing') then
        profz_eos=1.0
        dprofz_eos=0.0
      elseif (ieos_profile=='surface_z') then
        profz_eos=0.5*(1.0-erfunc(z/width_eos_prof))
        dprofz_eos=-exp(-(z/width_eos_prof)**2)/(sqrtpi*width_eos_prof)
      endif
!
    endsubroutine units_eos
!***********************************************************************
    subroutine initialize_eos()
!
      use Mpicomm, only: stop_it
      use SharedVariables, only: put_shared_variable
      use Sub, only: register_report_aux
!
      integer :: ierr
!
!  Perform any post-parameter-read initialization
!
!  Initialize variable selection code (needed for RELOADing).
!
      ieosvars=-1
      ieosvar_count=0
!
!  Write constants to disk. In future we may want to deal with this
!  using an include file or another module.
!
      if (lroot) then
        open (1,file=trim(datadir)//'/pc_constants.pro',position="append")
        write (1,'(a,1pd26.16)') 'k_B=',k_B
        write (1,'(a,1pd26.16)') 'm_H=',m_H
        write (1,*) 'lnrho0=',lnrho0
        write (1,*) 'lnTTO=',lnTT0
        write (1,*) 'cs20=',cs20
        write (1,*) 'cp=',cp
        close (1)
      endif
!
!  cs as optional auxiliary variable
!
      if (lcs_as_aux .or. lcs_as_comaux) &
          call register_report_aux('cs',ics,communicated=lcs_as_comaux)
!
      call put_shared_variable('cp',cp,ierr)
        if (ierr/=0) call stop_it("cp: "//&
             "there was a problem when sharing cp")
      call put_shared_variable('cv',cv,ierr)
        if (ierr/=0) call stop_it("cv: "//&
             "there was a problem when sharing cv")
      call put_shared_variable('isothmid',isothmid,ierr)
        if (ierr/=0) call stop_it("isothmid: "//&
             "there was a problem when sharing isothmid")
      call put_shared_variable('fac_cs',fac_cs,ierr)
        if (ierr/=0) call stop_it("fac_cs: "//&
             "there was a problem when sharing fac_cs")

      if (.not.ldensity) then
        call put_shared_variable('rho0',rho0,ierr)
        call put_shared_variable('lnrho0',lnrho0,ierr)
      endif
!
      if (.not.ldensity) then
        call put_shared_variable('rho0',rho0,ierr)
        if (ierr/=0) call stop_it("initialize_eos: "//&
             "there was a problem when sharing rho0")
        call put_shared_variable('lnrho0',lnrho0,ierr)      !caller='initialize_eos')
        if (ierr/=0) call stop_it("initialize_eos: "//&
             "there was a problem when sharing lnrho0")
      endif
!
      if (lanelastic) then
        call put_shared_variable('lanelastic_lin',lanelastic_lin,ierr)
        if (ierr/=0) call stop_it("lanelastic_lin: "//&
             "there was a problem when sharing lanelastic_lin")
      endif
!
!  Set background stratification, if any.
!
      if (lstratz) call set_stratz()
      lstratset = .true.
!
    endsubroutine initialize_eos
!***********************************************************************
    subroutine select_eos_variable(variable,findex)
!
!  Select eos variable.
!
!   02-apr-06/tony: implemented
!
      use FArrayManager, only: farray_register_global
!
      character (len=*), intent(in) :: variable
      integer, intent(in) :: findex
      integer :: this_var=-1
      integer, save :: ieosvar_selected=0
      integer, parameter :: ieosvar_lnrho = 2**0
      integer, parameter :: ieosvar_rho   = 2**1
      integer, parameter :: ieosvar_ss    = 2**2
      integer, parameter :: ieosvar_lnTT  = 2**3
      integer, parameter :: ieosvar_TT    = 2**4
      integer, parameter :: ieosvar_cs2   = 2**5
      integer, parameter :: ieosvar_pp    = 2**6
      integer, parameter :: ieosvar_eth   = 2**7
!
      if (ieosvar_count==0) ieosvar_selected=0
!
      if (ieosvar_count>=2) &
          call fatal_error('select_eos_variable', &
          '2 thermodynamic quantities have already been defined '// &
          'while attempting to add a 3rd')
!
      ieosvar_count=ieosvar_count+1
!
      if (variable=='ss') then
        this_var=ieosvar_ss
        if (findex<0) then
          leos_isentropic=.true.
        endif
      elseif (variable=='cs2') then
        this_var=ieosvar_cs2
        if (findex==-2) then
          leos_localisothermal=.true.
          call farray_register_global('cs2',iglobal_cs2)
          call farray_register_global('glnTT',iglobal_glnTT,vector=3)
        elseif (findex<0) then
          leos_isothermal=.true.
        endif
      elseif (variable=='lnTT') then
        this_var=ieosvar_lnTT
        if (findex<0) then
          leos_isothermal=.true.
        endif
      elseif (variable=='TT') then
        this_var=ieosvar_TT
      elseif (variable=='lnrho') then
        this_var=ieosvar_lnrho
        if (findex<0) then
          leos_isochoric=.true.
        endif
      elseif (variable=='rho') then
        this_var=ieosvar_rho
        if (findex<0) then
          leos_isochoric=.true.
        endif
      elseif (variable=='pp') then
        this_var=ieosvar_pp
        if (findex<0) then
          leos_isobaric=.true.
        endif
      elseif (variable=='eth') then
        this_var=ieosvar_eth
      else
        call fatal_error('select_eos_variable','unknown thermodynamic variable')
      endif
      if (ieosvar_count==1) then
        ieosvar1=findex
        ieosvar_selected=ieosvar_selected+this_var
        return
      endif
!
!  Ensure the indexes are in the correct order.
!
      if (this_var<ieosvar_selected) then
        ieosvar2=ieosvar1
        ieosvar1=findex
      else
        ieosvar2=findex
      endif
      ieosvar_selected=ieosvar_selected+this_var
      select case (ieosvar_selected)
        case (ieosvar_lnrho+ieosvar_ss)
          if (lroot) print*, 'select_eos_variable: Using lnrho and ss'
          ieosvars=ilnrho_ss
        case (ieosvar_rho+ieosvar_ss)
          if (lroot) print*, 'select_eos_variable: Using rho and ss'
          ieosvars=irho_ss
        case (ieosvar_lnrho+ieosvar_lnTT)
          if (lroot) print*, 'select_eos_variable: Using lnrho and lnTT'
          ieosvars=ilnrho_lnTT
        case (ieosvar_lnrho+ieosvar_TT)
          if (lroot) print*, 'select_eos_variable: Using lnrho and TT'
          ieosvars=ilnrho_TT
        case (ieosvar_rho+ieosvar_lnTT)
          if (lroot) print*, 'select_eos_variable: Using rho and lnTT'
          ieosvars=irho_lnTT
        case (ieosvar_lnrho+ieosvar_cs2)
          if (lroot) print*, 'select_eos_variable: Using lnrho and cs2'
          ieosvars=ilnrho_cs2
        case (ieosvar_rho+ieosvar_cs2)
          if (lroot) print*, 'select_eos_variable: Using rho and cs2'
          ieosvars=irho_cs2
        case (ieosvar_rho+ieosvar_TT)
          if (lroot) print*, 'select_eos_variable: Using rho and TT'
          ieosvars=irho_TT
        case (ieosvar_pp+ieosvar_ss)
          if (lroot) print*, 'select_eos_variable: Using pp and ss'
          ieosvars=ipp_ss
        case (ieosvar_pp+ieosvar_cs2)
          if (lroot) print*, 'select_eos_variable: Using pp and cs2'
          ieosvars=ipp_cs2
        case (ieosvar_rho+ieosvar_eth)
          if (lroot) print*, 'select_eos_variable: Using rho and eth'
          ieosvars=irho_eth
        case (ieosvar_lnrho+ieosvar_eth)
          if (lroot) print*, 'select_eos_variable: Using lnrho and eth'
          ieosvars=ilnrho_eth
        case default
          if (lroot) print*, 'select_eos_variable: '// &
              'Thermodynamic variable combination, ieosvar_selected =', &
              ieosvar_selected
          call fatal_error('select_eos_variable', &
              'This thermodynamic variable combination is not implemented')
      endselect
!
    endsubroutine select_eos_variable
!***********************************************************************
    subroutine getmu(f,mu_tmp)
!
!  Calculate average particle mass in the gas relative to
!
!   12-aug-03/tony: implemented
!
      real, dimension (mx,my,mz,mfarray), optional :: f
      real, intent(out) :: mu_tmp
!
!  mu = mu_H * (1 - xHe) + mu_He * xHe
!     = mu_H + (mu_He-mu_H) * xHe
!  mu_H = 1.
!  mu_He = 4.0026 / 1.0079  (molar masses from a Periodic Table)
!        = 3.97
!
      if (mu==0.0) then
        mu_tmp=1.0+2.97153*xHe
      else
        mu_tmp=mu
      endif
!
      call keep_compiler_quiet(present(f))
!
    endsubroutine getmu
!***********************************************************************
    subroutine getmu_array(f,mu1_full_tmp)
!
!  dummy routine to calculate mean molecular weight
!
!   16-mar-10/natalia
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz) :: mu1_full_tmp
!
      call keep_compiler_quiet(f)
      call keep_compiler_quiet(mu1_full_tmp)
!
    endsubroutine getmu_array
!***********************************************************************
    subroutine rprint_eos(lreset,lwrite)
!
!  Writes iyH and ilnTT to index.pro file.
!
      logical :: lreset
      logical, optional :: lwrite
!
      call keep_compiler_quiet(lreset)
      call keep_compiler_quiet(present(lwrite))
!
    endsubroutine rprint_eos
!***********************************************************************
    subroutine get_slices_eos(f,slices)
!
      real, dimension (mx,my,mz,mfarray) :: f
      type (slice_data) :: slices
!
      call keep_compiler_quiet(f)
      call keep_compiler_quiet(slices%ready)
!
    endsubroutine get_slices_eos
!***********************************************************************
    subroutine pencil_criteria_eos()
!
!  All pencils that the EquationOfState module depends on are specified here.
!
!  02-04-06/tony: coded
!
      if (lcs_as_aux.or.lcs_as_comaux) lpenc_requested(i_cs2)=.true.
!
    endsubroutine pencil_criteria_eos
!***********************************************************************
    subroutine pencil_interdep_eos(lpencil_in)
!
!  Interdependency among pencils from the EquationOfState module is specified
!  here.
!
!  20-nov-04/anders: coded
!  15-jul-10/axel: added gTT calculation for ilnrho_ss,irho_ss case
!
      logical, dimension(npencils) :: lpencil_in
!
      if (lpencil_in(i_cp)) lpencil_in(i_cp1)=.true.
!
      select case (ieosvars)
!
!  Pencils for thermodynamic quantities for given lnrho or rho and ss.
!
      case (ilnrho_ss,irho_ss)
        if (leos_isentropic) then
          if (lpencil_in(i_cs2)) lpencil_in(i_lnrho)=.true.
        elseif (leos_isothermal) then
          if (lpencil_in(i_ss)) lpencil_in(i_lnrho)=.true.
          if (lpencil_in(i_gss)) lpencil_in(i_glnrho)=.true.
          if (lpencil_in(i_hss)) lpencil_in(i_hlnrho)=.true.
          if (lpencil_in(i_del2ss)) lpencil_in(i_del2lnrho)=.true.
          if (lpencil_in(i_del6ss)) lpencil_in(i_del6lnrho)=.true.
        elseif (leos_localisothermal) then
        else
          if (lpencil_in(i_cs2)) then
            lpencil_in(i_ss)=.true.
            lpencil_in(i_lnrho)=.true.
          endif
        endif
        if (lpencil_in(i_lnTT)) then
          lpencil_in(i_ss)=.true.
          lpencil_in(i_lnrho)=.true.
        endif
        if (lpencil_in(i_pp)) then
          lpencil_in(i_lnTT)=.true.
          lpencil_in(i_lnrho)=.true.
        endif
        if (lpencil_in(i_ee)) lpencil_in(i_lnTT)=.true.
        if (lpencil_in(i_TT1)) lpencil_in(i_lnTT)=.true.
        if (lpencil_in(i_TT)) lpencil_in(i_lnTT)=.true.
        if (lpencil_in(i_glnTT)) then
          lpencil_in(i_glnrho)=.true.
          lpencil_in(i_gss)=.true.
        endif
        if (lpencil_in(i_gTT)) then
          lpencil_in(i_glnTT)=.true.
          lpencil_in(i_TT)=.true.
        endif
        if (lpencil_in(i_del2lnTT)) then
          lpencil_in(i_del2lnrho)=.true.
          lpencil_in(i_del2ss)=.true.
        endif
        if (lpencil_in(i_hlnTT)) then
          lpencil_in(i_hlnrho)=.true.
          lpencil_in(i_hss)=.true.
        endif
!
!  Pencils for thermodynamic quantities for given lnrho or rho and lnTT.
!
      case (ilnrho_lnTT,irho_lnTT)
        if (leos_isentropic) then
          if (lpencil_in(i_lnTT)) lpencil_in(i_lnrho)=.true.
          if (lpencil_in(i_glnTT)) lpencil_in(i_glnrho)=.true.
          if (lpencil_in(i_hlnTT)) lpencil_in(i_hlnrho)=.true.
          if (lpencil_in(i_del2lnTT)) lpencil_in(i_del2lnrho)=.true.
          if (lpencil_in(i_cs2)) lpencil_in(i_lnrho)=.true.
        elseif (leos_isothermal) then
        elseif (leos_localisothermal) then
        else
          if (lpencil_in(i_cs2)) lpencil_in(i_lnTT)=.true.
        endif
        if (lpencil_in(i_ss)) then
          lpencil_in(i_lnTT)=.true.
          lpencil_in(i_lnrho)=.true.
        endif
        if (lpencil_in(i_pp)) then
          lpencil_in(i_lnTT)=.true.
          lpencil_in(i_lnrho)=.true.
        endif
        if (lpencil_in(i_ee)) lpencil_in(i_lnTT)=.true.
        if (lpencil_in(i_TT)) lpencil_in(i_lnTT)=.true.
        if (lpencil_in(i_TT1)) lpencil_in(i_lnTT)=.true.
        if (lpencil_in(i_gss)) then
          lpencil_in(i_glnTT)=.true.
          lpencil_in(i_glnrho)=.true.
        endif
        if (lpencil_in(i_del2ss)) then
          lpencil_in(i_del2lnTT)=.true.
          lpencil_in(i_del2lnrho)=.true.
        endif
        if (lpencil_in(i_hss)) then
          lpencil_in(i_hlnTT)=.true.
          lpencil_in(i_hlnrho)=.true.
        endif
        if (lpencil_in(i_gTT)) then
          lpencil_in(i_glnTT)=.true.
        endif
!
!  Pencils for thermodynamic quantities for given lnrho or rho and TT.
!
      case (ilnrho_TT,irho_TT)
        if (lpencil_in(i_glnTT)) then
          lpencil_in(i_gTT)=.true.
          lpencil_in(i_TT1)=.true.
        endif
        if (lpencil_in(i_ss)) then
          lpencil_in(i_lnTT)=.true.
          lpencil_in(i_lnrho)=.true.
        endif
        if (lpencil_in(i_del2lnTT)) then
          lpencil_in(i_glnTT)=.true.
          lpencil_in(i_TT1)=.true.
        endif
!
!  Pencils for thermodynamic quantities for given lnrho or rho and cs2.
!
      case (ilnrho_cs2,irho_cs2)
        if (leos_isentropic) then
           call fatal_error('eos_isentropic', 'isentropic case not yet coded')
        elseif (leos_isothermal) then
          if (lpencil_in(i_ss)) lpencil_in(i_lnrho)=.true.
          if (lpencil_in(i_del2ss)) lpencil_in(i_del2lnrho)=.true.
          if (lpencil_in(i_gss)) lpencil_in(i_glnrho)=.true.
          if (lpencil_in(i_hss)) lpencil_in(i_hlnrho)=.true.
          if (lpencil_in(i_pp)) lpencil_in(i_rho)=.true.
        endif
!
!  Pencils for thermodynamic quantities for given pp and ss (anelastic case only).
!
      case(ipp_ss)
        if (leos_isentropic) then
           call fatal_error('eos_isentropic', 'isentropic case not yet coded')
        elseif (leos_isothermal) then
          if (lpencil_in(i_lnrho)) then
            lpencil_in(i_pp)=.true.
!            lpencil_in(i_TT)=.true.
          endif
          if (lpencil_in(i_rho)) lpencil_in(i_lnrho)=.true.
        else
          lpencil_in(i_rho)=.true.
          lpencil_in(i_pp)=.true.
          lpencil_in(i_ss)=.true.
          if (lpencil_in(i_lnrho)) lpencil_in(i_rho)=.true.
          if (lpencil_in(i_lnTT)) lpencil_in(i_lnrho)=.true.
          if (lpencil_in(i_lnTT)) lpencil_in(i_ss)=.true.
          if (lpencil_in(i_TT1)) lpencil_in(i_lnTT)=.true.
          if (lpencil_in(i_TT)) lpencil_in(i_lnTT)=.true.
!         if (lpencil_in(i_lnrho)) then
!           lpencil_in(i_pp)=.true.
!           lpencil_in(i_ss)=.true.
!         endif
          if (lpencil_in(i_rho_anel)) then
              lpencil_in(i_pp)=.true.
              lpencil_in(i_ss)=.true.
          endif
        endif
!
      case (ipp_cs2)
        if (leos_isentropic) then
           call fatal_error('eos_isentropic', 'isentropic case not yet coded')
        elseif (leos_isothermal) then
          if (lpencil_in(i_lnrho)) then
            lpencil_in(i_pp)=.true.
          endif
          if (lpencil_in(i_rho)) lpencil_in(i_lnrho)=.true.
        else
          if (lpencil_in(i_rho)) lpencil_in(i_lnrho)=.true.
          if (lpencil_in(i_TT1)) lpencil_in(i_TT)=.true.
          if (lpencil_in(i_TT)) lpencil_in(i_lnTT)=.true.
        endif
!
      case (irho_eth,ilnrho_eth)
        if (lstratz .and. lpencil_in(i_eth)) lpencil_in(i_eths) = .true.
        if (lpencil_in(i_cs2).or. &
            lpencil_in(i_TT).or. &
            lpencil_in(i_lnTT).or. &
            lpencil_in(i_TT1)) then
          lpencil_in(i_eth)=.true.
          lpencil_in(i_rho1)=.true.
        endif
        if (lpencil_in(i_pp)) lpencil_in(i_eth)=.true.
        if (lpencil_in(i_ee)) then
          lpencil_in(i_rho1)=.true.
          lpencil_in(i_eth)=.true.
        endif
        if (lpencil_in(i_TT)) then
          lpencil_in(i_cv1)=.true.
          lpencil_in(i_rho1)=.true.
          lpencil_in(i_eth)=.true.
        endif
        if (lpencil_in(i_lnTT)) lpencil_in(i_TT)=.true.
        if (lpencil_in(i_TT1)) lpencil_in(i_TT)=.true.
        if (lpencil_in(i_gTT).or.lpencil_in(i_glnTT)) then
          lpencil_in(i_rho1)=.true.
          lpencil_in(i_cv1)=.true.
          lpencil_in(i_geth)=.true.
          lpencil_in(i_TT)=.true.
          lpencil_in(i_TT1)=.true.
          lpencil_in(i_rho)=.true.
        endif
        if (lpencil_in(i_del2TT)) then
          lpencil_in(i_rho1)=.true.
          lpencil_in(i_cv1)=.true.
          lpencil_in(i_del2eth)=.true.
          lpencil_in(i_TT)=.true.
          lpencil_in(i_del2rho)=.true.
          lpencil_in(i_grho)=.true.
          lpencil_in(i_gTT)=.true.
        endif
        if (lpencil_in(i_ss)) then
          lpencil_in(i_cp)=.true.
          lpencil_in(i_TT)=.true.
        endif
      case default
        call fatal_error('pencil_interdep_eos','case not implemented yet')
      endselect
!
    endsubroutine pencil_interdep_eos
!***********************************************************************
    subroutine calc_pencils_eos(f,p)
!
!  Calculate EquationOfState pencils.
!  Most basic pencils should come first, as others may depend on them.
!
!  02-apr-06/tony: coded
!  20-jan-15/MR: changes for use of reference_state
!
      use Sub
      use SharedVariables, only: get_shared_variable
!
      real, dimension (mx,my,mz,mfarray) :: f
      type (pencil_case) :: p
!
      intent(inout) :: f
      intent(inout) :: p
!
      real, dimension(nx) :: tmp
      integer :: i,j
      real, dimension(:,:), pointer :: reference_state
!
!  Inverse cv and cp values.
!
      if (lpencil(i_cv1)) p%cv1=cv1
      if (lpencil(i_cp1)) p%cp1=cp1
      if (lpencil(i_cv))  p%cv=1/cv1
      if (lpencil(i_cp))  p%cp=1/cp1
      if (lpencil(i_cp1tilde)) p%cp1tilde=cp1
!
      if (lpencil(i_glnmumol)) p%glnmumol(:,:)=0.0
!
!  THE FOLLOWING 2 ARE CONCEPTUALLY WRONG
!  FOR pretend_lnTT since iss actually contain lnTT NOT entropy!
!  The code is not wrong however since this is correctly
!  handled by the eos module.
!
      select case (ieosvars)
!
!  Work out thermodynamic quantities for given lnrho or rho and ss.
!
      case (ilnrho_ss,irho_ss)
        if (leos_isentropic) then
          if (lpencil(i_ss)) p%ss=0.0
          if (lpencil(i_gss)) p%gss=0.0
          if (lpencil(i_hss)) p%hss=0.0
          if (lpencil(i_del2ss)) p%del2ss=0.0
          if (lpencil(i_del6ss)) p%del6ss=0.0
          if (lpencil(i_cs2)) p%cs2=cs20*exp(gamma_m1*(p%lnrho-lnrho0))
        elseif (leos_isothermal) then
          if (lpencil(i_ss)) p%ss=-(cp-cv)*(p%lnrho-lnrho0)
          if (lpencil(i_gss)) p%gss=-(cp-cv)*p%glnrho
          if (lpencil(i_hss)) p%hss=-(cp-cv)*p%hlnrho
          if (lpencil(i_del2ss)) p%del2ss=-(cp-cv)*p%del2lnrho
          if (lpencil(i_del6ss)) p%del6ss=-(cp-cv)*p%del6lnrho
          if (lpencil(i_cs2)) p%cs2=cs20
        elseif (leos_localisothermal) then
          call fatal_error('calc_pencils_eos','leos_localisothermal '// &
              'not implemented for ilnrho_ss, try ilnrho_cs2')
        else
          if (lreference_state) &
            call get_shared_variable('reference_state',reference_state,caller='calc_pencils_eos')

          if (lpencil(i_ss)) then
            p%ss=f(l1:l2,m,n,ieosvar2)
            if (lreference_state) p%ss=p%ss+reference_state(:,iref_s)
          endif

          if (lpencil(i_gss)) then
            call grad(f,ieosvar2,p%gss)
if (notanumber(p%gss)) then
          print*,'calc_penc_eos1: NaNs in p%gss'
print*, 'n,m,iproc=', n,m,iproc
print*, 'p%gss=', p%gss
          stop
        endif
            if (lreference_state) p%gss(:,1)=p%gss(:,1)+reference_state(:,iref_gs)
          endif
          if (lpencil(i_hss)) then
            call g2ij(f,ieosvar2,p%hss)
            if (lreference_state) p%hss(:,1,1)=p%hss(:,1,1)+reference_state(:,iref_d2s)
          endif
          if (lpencil(i_del2ss)) then
            call del2(f,ieosvar2,p%del2ss)
            if (lreference_state) p%del2ss=p%del2ss+reference_state(:,iref_d2s)
          endif
          if (lpencil(i_del6ss)) then
            call del6(f,ieosvar2,p%del6ss)
            if (lreference_state) p%del6ss=p%del6ss+reference_state(:,iref_d6s)
          endif
          if (lpencil(i_cs2)) p%cs2=cs20*exp(cv1*p%ss+gamma_m1*(p%lnrho-lnrho0))
        endif
!
        if (lpencil(i_lnTT)) p%lnTT=lnTT0+cv1*p%ss+gamma_m1*(p%lnrho-lnrho0)
        if (lpencil(i_pp)) p%pp=(cp-cv)*exp(p%lnTT+p%lnrho)
        if (lpencil(i_ee)) p%ee=cv*exp(p%lnTT)
        if (lpencil(i_yH)) p%yH=impossible
        if (lpencil(i_TT)) p%TT=exp(p%lnTT)
        if (lpencil(i_TT1)) p%TT1=exp(-p%lnTT)
        if (lpencil(i_glnTT)) p%glnTT=gamma_m1*p%glnrho+cv1*p%gss
if (notanumber(p%glnrho)) then
          print*,'calc_penc_eos: NaNs in p%glnrho'
          stop
        endif
        if (lpencil(i_gTT)) then
          do j=1,3; p%gTT(:,j)=p%glnTT(:,j)*p%TT; enddo
        endif
        if (lpencil(i_del2lnTT)) p%del2lnTT=gamma_m1*p%del2lnrho+cv1*p%del2ss
        if (lpencil(i_hlnTT)) p%hlnTT=gamma_m1*p%hlnrho+cv1*p%hss
!
!  Work out thermodynamic quantities for given lnrho or rho and lnTT.
!
      case (ilnrho_lnTT,irho_lnTT)
        if (leos_isentropic) then
          if (lpencil(i_lnTT)) p%lnTT=gamma_m1*(p%lnrho-lnrho0)+lnTT0
          if (lpencil(i_glnTT)) p%glnTT=gamma_m1*p%glnrho
          if (lpencil(i_hlnTT)) p%hlnTT=gamma_m1*p%hlnrho
          if (lpencil(i_del2lnTT)) p%del2lnTT=gamma_m1*p%del2lnrho
          if (lpencil(i_cs2)) p%cs2=cs20*exp(gamma_m1*(p%lnrho-lnrho0))
        elseif (leos_isothermal) then
          if (lpencil(i_lnTT)) p%lnTT=lnTT0
          if (lpencil(i_glnTT)) p%glnTT=0.0
          if (lpencil(i_hlnTT)) p%hlnTT=0.0
          if (lpencil(i_del2lnTT)) p%del2lnTT=0.0
          if (lpencil(i_cs2)) p%cs2=cs20
        elseif (leos_localisothermal) then
          call fatal_error('calc_pencils_eos','leos_localisothermal '// &
              'not implemented for ilnrho_ss, try ilnrho_cs2')
        else
          if (lpencil(i_lnTT)) p%lnTT=f(l1:l2,m,n,ieosvar2)
          if (lpencil(i_glnTT)) call grad(f,ieosvar2,p%glnTT)
          if (lpencil(i_hlnTT)) call g2ij(f,ieosvar2,p%hlnTT)
          if (lpencil(i_del2lnTT)) call del2(f,ieosvar2,p%del2lnTT)
          if (lpencil(i_del6lnTT)) call del6(f,ieosvar2,p%del6lnTT)
          if (lpencil(i_cs2)) p%cs2=cp*exp(p%lnTT)*gamma_m1
        endif
        if (lpencil(i_ss)) p%ss=cv*(p%lnTT-lnTT0-gamma_m1*(p%lnrho-lnrho0))
        if (lpencil(i_pp)) p%pp=(cp-cv)*exp(p%lnTT+p%lnrho)
        if (lpencil(i_ee)) p%ee=cv*exp(p%lnTT)
        if (lpencil(i_yH)) p%yH=impossible
        if (lpencil(i_TT)) p%TT=exp(p%lnTT)
        if (lpencil(i_TT1)) p%TT1=exp(-p%lnTT)
        if (lpencil(i_gss)) p%gss=cv*(p%glnTT-gamma_m1*p%glnrho)
        if (lpencil(i_del2ss)) p%del2ss=cv*(p%del2lnTT-gamma_m1*p%del2lnrho)
        if (lpencil(i_hss)) p%hss=cv*(p%hlnTT-gamma_m1*p%hlnrho)
        if (lpencil(i_gTT)) then
          do i=1,3; p%gTT(:,i)=p%TT*p%glnTT(:,i); enddo
        endif
        if (lpencil(i_del6ss)) call fatal_error('calc_pencils_eos', &
            'del6ss not available for ilnrho_lnTT')
!
!  Work out thermodynamic quantities for given lnrho or rho and TT.
!
      case (ilnrho_TT,irho_TT)
        if (lpencil(i_TT))   p%TT=f(l1:l2,m,n,ieosvar2)
        if (lpencil(i_TT1).or.lpencil(i_hlnTT))  p%TT1=1/f(l1:l2,m,n,ieosvar2)
        if (lpencil(i_lnTT).or.lpencil(i_ss).or.lpencil(i_ee)) &
            p%lnTT=log(f(l1:l2,m,n,ieosvar2))
        if (lpencil(i_cs2))  p%cs2=cp*gamma_m1*f(l1:l2,m,n,ieosvar2)
        if (lpencil(i_gTT))  call grad(f,ieosvar2,p%gTT)
        if (lpencil(i_glnTT).or.lpencil(i_hlnTT)) then
          do i=1,3; p%glnTT(:,i)=p%gTT(:,i)*p%TT1; enddo
        endif
        if (lpencil(i_del2TT).or.lpencil(i_del2lnTT)) &
            call del2(f,ieosvar2,p%del2TT)
        if (lpencil(i_del2lnTT)) then
          tmp=0.0
          do i=1,3
            tmp=tmp+p%glnTT(:,i)**2
          enddo
          p%del2lnTT=p%del2TT*p%TT1-tmp
        endif
        if (lpencil(i_hlnTT)) then
          call g2ij(f,iTT,p%hlnTT)
          do i=1,3; do j=1,3
            p%hlnTT(:,i,j)=p%hlnTT(:,i,j)*p%TT1-p%glnTT(:,i)*p%glnTT(:,j)
          enddo; enddo
        endif
        if (lpencil(i_del6TT)) call del6(f,ieosvar2,p%del6TT)
        if (lpencil(i_ss)) p%ss=cv*(p%lnTT-lnTT0-gamma_m1*(p%lnrho-lnrho0))
        if (lpencil(i_pp)) p%pp=cv*gamma_m1*p%rho*p%TT
        if (lpencil(i_ee)) p%ee=cv*exp(p%lnTT)
!
!  Work out thermodynamic quantities for given lnrho or rho and cs2.
!
      case (ilnrho_cs2,irho_cs2)
        if (leos_isentropic) then
          call fatal_error('calc_pencils_eos', &
              'leos_isentropic not implemented for ilnrho_cs2, try ilnrho_ss')
        elseif (leos_isothermal) then
          if (lpencil(i_cs2)) p%cs2=cs20
          if (lpencil(i_lnTT)) p%lnTT=lnTT0
          if (lpencil(i_glnTT)) p%glnTT=0.0
          if (lpencil(i_hlnTT)) p%hlnTT=0.0
          if (lpencil(i_del2lnTT)) p%del2lnTT=0.0
          if (lpencil(i_ss)) p%ss=-(cp-cv)*(p%lnrho-lnrho0)
          if (lpencil(i_del2ss)) p%del2ss=-(cp-cv)*p%del2lnrho
          if (lpencil(i_gss)) p%gss=-(cp-cv)*p%glnrho
          if (lpencil(i_hss)) p%hss=-(cp-cv)*p%hlnrho
          if (lpencil(i_pp)) p%pp=gamma1*p%rho*cs20
        elseif (leos_localisothermal) then
          if (lpencil(i_cs2)) p%cs2=f(l1:l2,m,n,iglobal_cs2)
          if (lpencil(i_lnTT)) call fatal_error('calc_pencils_eos', &
              'temperature not needed for localisothermal')
          if (lpencil(i_glnTT)) &
              p%glnTT=f(l1:l2,m,n,iglobal_glnTT:iglobal_glnTT+2)
          if (lpencil(i_hlnTT)) call fatal_error('calc_pencils_eos', &
              'no gradients yet for localisothermal')
          if (lpencil(i_del2lnTT)) call fatal_error('calc_pencils_eos', &
              'no gradients yet for localisothermal')
          if (lpencil(i_ss)) call fatal_error('calc_pencils_eos', &
              'entropy not needed for localisothermal')
          if (lpencil(i_del2ss)) call fatal_error('calc_pencils_eos', &
              'no gradients yet for localisothermal')
          if (lpencil(i_gss)) call fatal_error('calc_pencils_eos', &
              'entropy gradient not needed for localisothermal')
          if (lpencil(i_hss)) call fatal_error('calc_pencils_eos', &
              'no gradients yet for localisothermal')
          if (lpencil(i_pp)) p%pp=p%rho*p%cs2
        else
          call fatal_error('calc_pencils_eos', &
              'Full equation of state not implemented for ilnrho_cs2')
        endif
!
!  Work out thermodynamic quantities for given pp and ss (anelastic case).
!
      case (ipp_ss)
        if (lanelastic) then
          if (lanelastic_lin) then
            p%pp=f(l1:l2,m,n,ipp)
            p%ss=f(l1:l2,m,n,iss)
            p%TTb=cs20*cp1*exp(gamma*f(l1:l2,m,n,iss_b)*cp1+gamma_m1*p%lnrho)/gamma_m1
            p%cs2=cp*p%TTb*gamma_m1
            p%TT1=1./p%TTb
            p%rho_anel=(f(l1:l2,m,n,ipp)/(f(l1:l2,m,n,irho_b)*p%cs2)- &
                 f(l1:l2,m,n,iss)*cp1)
          else
            if (lpencil(i_pp)) p%pp=f(l1:l2,m,n,ipp)
            if (lpencil(i_ss)) p%ss=f(l1:l2,m,n,iss)
            if (lpencil(i_rho)) p%rho=f(l1:l2,m,n,irho)
            !if (lpencil(i_rho)) p%rho=rho0*(gamma*p%pp/(rho0*cs20*exp(cv1*p%ss)))**gamma1
            if (lpencil(i_lnrho)) p%lnrho=alog(p%rho)
            if (lpencil(i_cs2)) p%cs2=gamma*p%pp/p%rho
            if (lpencil(i_lnTT)) p%lnTT=lnTT0+cv1*p%ss+gamma_m1*(p%lnrho-lnrho0)
            if (lpencil(i_ee)) p%ee=cv*exp(p%lnTT)
            if (lpencil(i_yH)) p%yH=impossible
            if (lpencil(i_TT)) p%TT=exp(p%lnTT)
            if (lpencil(i_TT1)) p%TT1=exp(-p%lnTT)
          endif
        endif
        if (leos_isentropic) then
          if (lpencil(i_ss)) p%ss=0.0
          if (lpencil(i_lnrho)) p%lnrho=log(gamma*p%pp/(rho0*cs20))/gamma
          if (lpencil(i_rho)) p%rho=exp(log(gamma*p%pp/(rho0*cs20))/gamma)
          if (lpencil(i_TT)) p%TT=(p%pp/pp0)**(1.-gamma1)
          if (lpencil(i_lnTT)) p%lnTT=(1.-gamma1)*log(gamma*p%pp/(rho0*cs0))
          if (lpencil(i_cs2)) p%cs2=cs20*(p%pp/pp0)**(1.-gamma1)
        elseif (leos_isothermal) then
          if (lpencil(i_lnrho)) p%lnrho=log(gamma*p%pp/(cs20*rho0))-p%lnTT
          if (lpencil(i_rho)) p%rho=exp(p%lnrho)
          if (lpencil(i_cs2)) p%cs2=cs20
          if (lpencil(i_lnTT)) p%lnTT=lnTT0
          if (lpencil(i_glnTT)) p%glnTT=0.0
          if (lpencil(i_hlnTT)) p%hlnTT=0.0
          if (lpencil(i_del2lnTT)) p%del2lnTT=0.0
        elseif (leos_localisothermal) then
          call fatal_error('calc_pencils_eos', &
              'Local Isothermal case not implemented for ipp_ss')
        endif
!
      case (ipp_cs2)
        if (leos_isentropic) then
          call fatal_error('calc_pencils_eos', &
              'isentropic not implemented for (pp,lnTT)')
        elseif (leos_isothermal) then
        if (lanelastic) then
          if (lanelastic_lin) then
            p%pp=f(l1:l2,m,n,ipp)
            p%rho_anel=f(l1:l2,m,n,ipp)/(f(l1:l2,m,n,irho_b)*cs20)
          else  ! lanelastic_lin=F means the non-linearized anelastic approx.
            p%pp=f(l1:l2,m,n,ipp)
          endif
        else
          if (lpencil(i_cs2)) p%cs2=cs20
          if (lpencil(i_lnrho)) p%lnrho=log(p%pp/cs20)
          if (lpencil(i_rho)) p%rho=(p%pp/cs20)
          if (lpencil(i_lnTT)) p%lnTT=lnTT0
          if (lpencil(i_glnTT)) p%glnTT=0.0
          if (lpencil(i_hlnTT)) p%hlnTT=0.0
          if (lpencil(i_del2lnTT)) p%del2lnTT=0.0
        endif
        elseif (leos_localisothermal) then
          call fatal_error('calc_pencils_eos', &
              'Local Isothermal case not implemented for ipp_cs2')
        endif
!
!  Internal energy.
!  For gamma=1, we use R/mu = c_p = c_v, thus ee = c_vT = R/mu T = p/rho = cs^2.
!
        if (lpencil(i_ee)) then
          if (gamma_m1/=0.0) then
            p%ee=(gamma1/gamma_m1)*p%cs2
          else
            p%ee=p%cs2
          endif
        endif
        if (lpencil(i_yH)) p%yH=impossible
        if (lpencil(i_TT)) p%TT=exp(p%lnTT)
        if (lpencil(i_TT1)) p%TT1=exp(-p%lnTT)
        if (lpencil(i_del6ss)) call fatal_error('calc_pencils_eos', &
            'del6ss not available for ilnrho_cs2')
!
!  Work out thermodynamic quantities for given lnrho or rho and eth.
!
      case (irho_eth,ilnrho_eth)
        stratz: if (lstratz) then
          if (lpencil(i_eths)) p%eths = 1.0 + f(l1:l2,m,n,ieth)
          if (lpencil(i_geths)) call grad(f, ieth, p%geths)
          if (lpencil(i_eth)) p%eth = eth0z(n) * p%eths
          if (lpencil(i_geth)) call fatal_error('calc_pencils_eos', 'geth is not available. ')
          if (lpencil(i_del2eth)) call fatal_error('calc_pencils_eos', 'del2eth is not available. ')
        else stratz
          if (lpencil(i_eth)) p%eth = f(l1:l2,m,n,ieth)
          if (lpencil(i_geth)) call grad(f, ieth, p%geth)
          if (lpencil(i_del2eth)) call del2(f, ieth, p%del2eth)
          if (lpencil(i_eths)) call fatal_error('calc_pencils_eos', 'eths is not available. ')
          if (lpencil(i_geths)) call fatal_error('calc_pencils_eos', 'geths is not available. ')
        endif stratz
        if (lpencil(i_cs2)) p%cs2=gamma*gamma_m1*p%eth*p%rho1
        if (lpencil(i_pp)) p%pp=gamma_m1*p%eth
        if (lpencil(i_ee)) p%ee=p%rho1*p%eth
        if (lpencil(i_TT)) p%TT=p%cv1*p%rho1*p%eth
        if (lpencil(i_lnTT)) p%lnTT=alog(p%TT)
        if (lpencil(i_TT1)) p%TT1=1/p%TT
        if (lpencil(i_gTT).or.lpencil(i_glnTT)) then
          do i=1,3
            p%gTT(:,i)=p%rho1*(p%cv1*p%geth(:,i)-p%TT*p%grho(:,i))
            p%glnTT(:,i)=p%TT1*p%gTT(:,i)
          enddo
        endif
        if (lpencil(i_del2TT)) p%del2TT= &
            p%rho1*(p%cv1*p%del2eth-p%TT*p%del2rho-2*sum(p%grho*p%gTT,2))
        if (lpencil(i_hlnTT)) call fatal_error('calc_pencils_eos', &
            'hlnTT not yet implemented for ilnrho_eth or irho_eth')
!
      case default
        call fatal_error('calc_pencils_eos','case not implemented yet')
      endselect
!
!  cs as optional auxiliary variables
!
      if (lcs_as_aux.or.lcs_as_comaux) f(l1:l2,m,n,ics)=sqrt(p%cs2)
!
    endsubroutine calc_pencils_eos
!***********************************************************************
    subroutine ioninit(f)
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
!
      call keep_compiler_quiet(f)
!
    endsubroutine ioninit
!***********************************************************************
    subroutine ioncalc(f)
!
    real, dimension(mx,my,mz,mfarray), intent(in) :: f
!
    call keep_compiler_quiet(f)
!
    endsubroutine ioncalc
!***********************************************************************
    subroutine getdensity(EE,TT,yH,rho)
!
      real, intent(in) :: EE,TT,yH
      real, intent(inout) :: rho
!
      rho = EE * cv1 / TT
      call keep_compiler_quiet(yH)
!
    endsubroutine getdensity
!***********************************************************************
  subroutine gettemperature(f,TT_tmp)
!
     real, dimension (mx,my,mz,mfarray) :: f
     real, dimension (mx,my,mz), intent(out) :: TT_tmp
!
     call keep_compiler_quiet(f)
     call keep_compiler_quiet(TT_tmp)
!
   endsubroutine gettemperature
!***********************************************************************
   subroutine getpressure(pp_tmp)
!
     real, dimension (mx,my,mz), intent(out) :: pp_tmp
!
     call keep_compiler_quiet(pp_tmp)
!
   endsubroutine getpressure
!***********************************************************************
    subroutine get_cp1(cp1_)
!
!  04-nov-06/axel: added to alleviate spurious use of pressure_gradient
!
!  return the value of cp1 to outside modules
!
      real, intent(out) :: cp1_
!
      cp1_=cp1
!
    endsubroutine get_cp1
!***********************************************************************
    subroutine get_cv1(cv1_)
!
!  22-dec-10/PJK: adapted from get_cp1
!
!  return the value of cv1 to outside modules
!
      real, intent(out) :: cv1_
!
      cv1_=cv1
!
    endsubroutine get_cv1
!***********************************************************************
    subroutine pressure_gradient_farray(f,cs2,cp1tilde)
!
!   Calculate thermodynamical quantities, cs2 and cp1tilde
!   and optionally glnPP and glnTT
!   gP/rho=cs2*(glnrho+cp1tilde*gss)
!
!   17-nov-03/tobi: adapted from subroutine eoscalc
!   20-jan-15/MR: changes for use of reference state
!
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho
!
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      real, dimension(nx), intent(out) :: cs2,cp1tilde
!
      real, dimension(nx) :: lnrho,ss
      real, dimension(:,:), pointer :: reference_state
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state, &
                                 caller='pressure_gradient_farray')
!
      call getlnrho(f(:,m,n,ilnrho),lnrho)
!
      ss=f(l1:l2,m,n,iss)
      if (lreference_state) ss=ss+reference_state(:,iref_s)
!
!  pretend_lnTT
!
      if (pretend_lnTT) then
        cs2=gamma_m1*exp(cv1*ss)
      else
        cs2=cs20*exp(cv1*ss+gamma_m1*(lnrho-lnrho0))
      endif
!! Actual pressure gradient calculation:
!!          do j=1,3
!!            ju=j+iuu-1
!!            if (pretend_lnTT) then
!!              df(l1:l2,m,n,ju) = df(l1:l2,m,n,ju) - &
!!                  p%cs2*(p%glnrho(:,j)/gamma + p%cp1tilde*p%gss(:,j))
!!            else
!!              df(l1:l2,m,n,ju) = df(l1:l2,m,n,ju) - &
!!                  p%cs2*(p%glnrho(:,j) + p%cp1tilde*p%gss(:,j))
!!            endif
!!           enddo
!
!  inverse cp (will be different from 1 when cp is not 1)
!
      cp1tilde=cp1
!
    endsubroutine pressure_gradient_farray
!***********************************************************************
    subroutine pressure_gradient_point(lnrho,ss,cs2,cp1tilde)
!
!   Calculate thermodynamical quantities, cs2 and cp1tilde
!   and optionally glnPP and glnTT
!   gP/rho=cs2*(glnrho+cp1tilde*gss)
!
!   17-nov-03/tobi: adapted from subroutine eoscalc
!
      real, intent(in) :: lnrho,ss
      real, intent(out) :: cs2,cp1tilde
!
!  pretend_lnTT
!
      if (pretend_lnTT) then
        cs2=gamma_m1*exp(gamma*cp1*ss)
      else
        cs2=cs20*exp(cv1*ss+gamma_m1*(lnrho-lnrho0))
      endif
      cp1tilde=cp1
!
    endsubroutine pressure_gradient_point
!***********************************************************************
    subroutine temperature_gradient(f,glnrho,gss,glnTT)
!
!   Calculate thermodynamical quantities
!   and optionally glnPP and glnTT
!   gP/rho=cs2*(glnrho+cp1*gss)
!
!   17-nov-03/tobi: adapted from subroutine eoscalc
!
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      real, dimension(nx,3), intent(in) :: glnrho,gss
      real, dimension(nx,3), intent(out) :: glnTT
!
      if (gamma_m1==0.) call fatal_error('temperature_gradient', &
        'gamma=1 not allowed with entropy turned on!')
!
!  pretend_lnTT
!
      if (pretend_lnTT) then
        glnTT=gss
      else
        glnTT=gamma_m1*glnrho+cv1*gss
      endif
!
      call keep_compiler_quiet(f)
!
    endsubroutine temperature_gradient
!***********************************************************************
    subroutine temperature_laplacian(f,p)
!
!   Calculate thermodynamical quantities
!   and optionally glnPP and glnTT
!   gP/rho=cs2*(glnrho+cp1*gss)
!
!   17-nov-03/tobi: adapted from subroutine eoscalc
!
      use Sub, only: dot2
!
      type (pencil_case) :: p
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      real, dimension(nx) :: tmp
!
      if (gamma_m1==0.) &
           call fatal_error('temperature_laplacian', &
               'gamma=1 not allowed w/entropy')
!
!  pretend_lnTT
!
      if (pretend_lnTT) then
        p%del2lnTT=p%del2ss
      else
        if (ldensity_nolog) then
          call dot2(p%grho,tmp)
          p%del2lnTT=gamma_m1*p%rho1*(p%del2rho+p%rho1*tmp)
        else
          p%del2lnTT=gamma_m1*p%del2lnrho+p%cv1*p%del2ss
        endif
      endif
!
      call keep_compiler_quiet(f)
!
    endsubroutine temperature_laplacian
!***********************************************************************
    subroutine temperature_hessian(f,hlnrho,hss,hlnTT)
!
!   Calculate thermodynamical quantities, cs2 and cp1
!   and optionally hlnPP and hlnTT
!   hP/rho=cs2*(hlnrho+cp1*hss)
!
!   17-nov-03/tobi: adapted from subroutine eoscalc
!
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      real, dimension(nx,3,3), intent(in) :: hlnrho,hss
      real, dimension(nx,3,3), intent(out) :: hlnTT
!
      if (gamma_m1==0.) call fatal_error('temperature_hessian','gamma=1 not allowed w/entropy')
!
!  pretend_lnTT
!
      if (pretend_lnTT) then
        hlnTT=hss
      else
        hlnTT=gamma_m1*hlnrho+cv1*hss
      endif
!
      call keep_compiler_quiet(f)
!
    endsubroutine temperature_hessian
!***********************************************************************
    subroutine thermal_energy_hessian(f,ivar_eth,del2lneth,hlneth)
!
      use Sub, only: g2ij,grad,dot2
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (nx) :: del2lneth,del2eth,geth2,eth_1
      real, dimension (nx,3,3) :: hlneth,heth
      real, dimension (nx,3) :: geth
      integer :: ivar_eth,i,j
!
      intent (in) :: f,ivar_eth
      intent (out) :: del2lneth,hlneth
!
      call g2ij(f,ivar_eth,heth)
      call grad(f,ivar_eth,geth)
!
      call dot2(geth,geth2)
!
      del2eth = heth(:,1,1) + heth(:,2,2) + heth(:,3,3)
!
      eth_1 = 1./f(l1:l2,m,n,ivar_eth)
!
      del2lneth = eth_1*del2eth - eth_1*eth_1*geth2
!
      do i=1,3
        do j=1,3
          hlneth(:,i,j) = eth_1*(heth(:,i,j) - eth_1*geth(:,i)*geth(:,j))
        enddo
      enddo
!
    endsubroutine thermal_energy_hessian
!***********************************************************************
    subroutine eosperturb(f,psize,ee,pp,ss)
!
!  Set f(l1:l2,m,n,iss), depending on the values of ee and pp
!  Adding pressure perturbations is not implemented
!
!  20-jan-15/MR: changes for use of reference state
!
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho
!
      real, dimension(mx,my,mz,mfarray), intent(inout) :: f
      integer, intent(in) :: psize
      real, dimension(psize), intent(in), optional :: ee, pp, ss
!
      real, dimension(psize) :: lnrho_
      real, dimension(:,:), pointer :: reference_state
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='eosperturb')

      if (psize==nx) then
        call getlnrho(f(:,m,n,ilnrho),lnrho_)
        if (present(ee)) then
          if (pretend_lnTT) then
            f(l1:l2,m,n,iss)=log(cv1*ee)
          else
            f(l1:l2,m,n,iss)=cv*(log(cv1*ee)-lnTT0-gamma_m1*(lnrho_-lnrho0))
          endif
        elseif (present(pp)) then
          if (pretend_lnTT) then
            f(l1:l2,m,n,iss)=log(gamma*pp/(gamma_m1*lnrho_))
          else
            f(l1:l2,m,n,iss)=cv*(log(gamma*pp/gamma_m1)-gamma*lnrho_-gamma_m1*lnrho0-lnTT0)
          endif
        elseif (present(ss)) then
          if (pretend_lnTT) then
            f(l1:l2,m,n,iss)=lnTT0+cv1*ss+gamma_m1*(lnrho_-lnrho0)
          else
            f(l1:l2,m,n,iss)=ss
          endif
        endif
!
        if (lreference_state) f(l1:l2,m,n,iss) = f(l1:l2,m,n,iss) - reference_state(:,iref_s)
!
      elseif (psize==mx) then
!
!  Reference state not yet considered in this branch as undefined in ghost zones.
!
        if (ldensity_nolog) then
          lnrho_=log(f(:,m,n,irho))
        else
          lnrho_=f(:,m,n,ilnrho)
        endif
        if (present(ee)) then
          if (pretend_lnTT) then
            f(:,m,n,iss)=log(cv1*ee)
          else
            f(:,m,n,iss)=cv*(log(cv1*ee)-lnTT0-gamma_m1*(lnrho_-lnrho0))
          endif
        elseif (present(pp)) then
          if (pretend_lnTT) then
            f(:,m,n,iss)=log(gamma*pp/(gamma_m1*lnrho_))
          else
            f(:,m,n,iss)=cv*(log(gamma*pp/gamma_m1)-gamma*lnrho_-gamma_m1*lnrho0-lnTT0)
          endif
        elseif (present(ss)) then
          if (pretend_lnTT) then
            f(:,m,n,iss)=lnTT0+cv1*ss+gamma_m1*(lnrho_-lnrho0)
          else
            f(:,m,n,iss)=ss
          endif
        endif
!
      else
        call not_implemented("eosperturb")
      endif
    endsubroutine eosperturb
!***********************************************************************
    subroutine eoscalc_farray(f,psize,lnrho,yH,lnTT,ee,pp,cs2,kapparho)
!
!   Calculate thermodynamical quantities
!
!   02-feb-03/axel: simple example coded
!   13-jun-03/tobi: the ionization fraction as part of the f-array
!                   now needs to be given as an argument as input
!   17-nov-03/tobi: moved calculation of cs2 and cp1 to
!                   subroutine pressure_gradient
!   12-feb-15/MR  : changes for reference state
!
      use Diagnostics, only: max_mn_name, sum_mn_name
      use SharedVariables, only: get_shared_variable
!
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      integer, intent(in) :: psize
      real, dimension(psize), intent(out), optional :: lnrho
      real, dimension(psize), intent(out), optional :: yH,ee,pp,kapparho
      real, dimension(psize), intent(out), optional :: lnTT
      real, dimension(psize), intent(out), optional :: cs2
      real, dimension(psize) :: lnTT_, cs2_
      real, dimension(psize) :: lnrho_,ss_
      real, dimension(psize) :: rho, eth
      real, dimension(:,:), pointer :: reference_state
!
!ajwm this test should be done at initialization
!      if (gamma_m1==0.) call fatal_error('eoscalc_farray','gamma=1 not allowed w/entropy')
!
      select case (ieosvars)
!
! Log rho and entropy
!
      case (ilnrho_ss,irho_ss)
        if (lreference_state) &
          call get_shared_variable('reference_state',reference_state,caller='eoscalc_farray')

        select case (psize)
        case (nx)
          if (lstratz) then
            lnrho_ = log(rho0z(n)) + log(1.0 + f(l1:l2,m,n,ieosvar1))
          elseif (ieosvars == ilnrho_ss) then    ! use of getlnrho possible?
            lnrho_=f(l1:l2,m,n,ieosvar1)
          else
            if (lreference_state) then
              lnrho_=log(f(l1:l2,m,n,ieosvar1)+reference_state(:,iref_rho))
            else
              lnrho_=log(f(l1:l2,m,n,ieosvar1))
            endif
          endif
          if (leos_isentropic) then
            ss_=0
          elseif (leos_isothermal) then
            ss_=-cv*gamma_m1*(lnrho_-lnrho0)
          else
            ss_=f(l1:l2,m,n,ieosvar2)
            if (lreference_state) ss_ = ss_+reference_state(:,iref_s)
          endif
        case (mx)
          if (lstratz) then
            lnrho_ = log(rho0z(n)) + log(1.0 + f(:,m,n,ieosvar1))
          elseif (ieosvars == ilnrho_ss) then
            lnrho_=f(:,m,n,ieosvar1)
          else
            !!!if (lreference_state) then
            lnrho_=log(f(:,m,n,ieosvar1))
          endif
          if (leos_isentropic) then
            ss_=0
          elseif (leos_isothermal) then
            ss_=-cv*gamma_m1*(lnrho_-lnrho0)
          else
            !!!if (lreference_state) then
            ss_=f(:,m,n,ieosvar2)
          endif
        case default
          call fatal_error('eoscalc_farray','no such pencil size')
        end select
!
        lnTT_=lnTT0+cv1*ss_+gamma_m1*(lnrho_-lnrho0)
        if (gamma_m1==0.) &
            call fatal_error('eoscalc_farray','gamma=1 not allowed w/entropy')
        if (present(lnrho)) lnrho=lnrho_
        if (present(lnTT)) lnTT=lnTT_
        if (present(ee)) ee=cv*exp(lnTT_)
        if (present(pp)) pp=(cp-cv)*exp(lnTT_+lnrho_)
        if (present(cs2)) call fatal_error('eoscalc_farray', 'cs2 is not implemented. ')
!
! Log rho and Log T
!
      case (ilnrho_lnTT,irho_lnTT)
        select case (psize)
        case (nx)
          if (ieosvars==ilnrho_lnTT) then
            lnrho_=f(l1:l2,m,n,ieosvar1)
          else
            lnrho_=log(f(l1:l2,m,n,ieosvar1))
          endif
          if (leos_isentropic) then
            lnTT_=lnTT0+(cp-cv)*(lnrho_-lnrho0)
          elseif (leos_isothermal) then
            lnTT_=lnTT0
          else
            lnTT_=f(l1:l2,m,n,ieosvar2)
          endif
        case (mx)
          if (ieosvars==ilnrho_lnTT) then
            lnrho_=f(:,m,n,ieosvar1)
          else
            lnrho_=log(f(:,m,n,ieosvar1))
          endif
          if (leos_isentropic) then
            lnTT_=lnTT0+(cp-cv)*(lnrho_-lnrho0)
          elseif (leos_isothermal) then
            lnTT_=lnTT0
          else
            lnTT_=f(:,m,n,ieosvar2)
          endif
        case default
          call fatal_error('eoscalc_farray','no such pencil size')
        end select
!
        if (present(lnrho)) lnrho=lnrho_
        if (present(lnTT)) lnTT=lnTT_
        if (present(ee)) ee=cv*exp(lnTT_)
        if (present(pp)) pp=(cp-cv)*exp(lnTT_+lnrho_)
        if (present(cs2)) call fatal_error('eoscalc_farray', 'cs2 is not implemented. ')
!
! Log rho or rho and T
!
      case (ilnrho_TT,irho_TT)
          call fatal_error('eoscalc_farray','no implemented for lnrho_TT or rho_TT')
!
! Log rho and cs2
!
      case (ilnrho_cs2,irho_cs2)
        select case (psize)
        case (nx)
          if (lstratz) then
            lnrho_ = log(rho0z(n)) + log(1 + f(l1:l2,m,n,ieosvar1))
          elseif (ieosvars == ilnrho_cs2) then
            lnrho_=f(l1:l2,m,n,ieosvar1)
          else
            lnrho_=log(f(l1:l2,m,n,ieosvar1))
          endif
          if (leos_isentropic) then
            cs2_=exp(gamma_m1*(lnrho_-lnrho0)+log(cs20))
          elseif (leos_isothermal) then
            cs2_=cs20
          elseif (leos_localisothermal) then
            cs2_=f(l1:l2,m,n,iglobal_cs2)
          else
            call fatal_error('eoscalc_farray','full eos for cs2 not implemented')
          endif
        case (mx)
          if (lstratz) then
            lnrho_ = log(rho0z(n)) + log(1 + f(:,m,n,ieosvar1))
          elseif (ieosvars == ilnrho_cs2) then
            lnrho_=f(:,m,n,ieosvar1)
          else
            lnrho_=log(f(:,m,n,ieosvar1))
          endif
          if (leos_isentropic) then
            cs2_=exp(gamma_m1*(lnrho_-lnrho0)+log(cs20))
          elseif (leos_isothermal) then
            cs2_=cs20
          elseif (leos_localisothermal) then
            cs2_=f(:,m,n,iglobal_cs2)
          else
            call fatal_error('eoscalc_farray','full eos for cs2 not implemented')
          endif
        case default
          call fatal_error('eoscalc_farray','no such pencil size')
        end select
!
        if (present(lnrho)) lnrho=lnrho_
        if (present(lnTT)) lnTT=lnTT0+log(cs2_)
        if (present(ee)) ee=gamma1*cs2_/gamma_m1
        if (present(pp)) pp=gamma1*cs2_*exp(lnrho_)
        if (present(cs2)) cs2 = cs2_
!
      case (irho_eth, ilnrho_eth)
        rho_eth: select case (psize)
        case (nx) rho_eth
          strat1: if (lstratz) then
            rho = rho0z(n) * (1.0 + f(l1:l2,m,n,irho))
            eth = eth0z(n) * (1.0 + f(l1:l2,m,n,ieth))
          else strat1
            if (ldensity_nolog) then
              rho = f(l1:l2,m,n,irho)
            else
              rho = exp(f(l1:l2,m,n,ilnrho))
            endif
            eth = f(l1:l2,m,n,ieth)
          endif strat1
        case (mx) rho_eth
          strat2: if (lstratz) then
            rho = rho0z(n) * (1.0 + f(:,m,n,irho))
            eth = eth0z(n) * (1.0 + f(:,m,n,ieth))
          else strat2
            if (ldensity_nolog) then
              rho = f(:,m,n,irho)
            else
              rho = exp(f(:,m,n,ilnrho))
            endif
            eth = f(:,m,n,ieth)
          endif strat2
        case default rho_eth
          call fatal_error('eoscalc_farray', 'no such pencil size')
        endselect rho_eth
        if (present(lnrho)) lnrho = log(rho)
        if (present(lnTT)) lnTT = log(cv1 * eth / rho)
        if (present(ee)) ee = eth / rho
        if (present(pp)) pp = gamma_m1 * eth
        if (present(cs2)) cs2 = gamma * gamma_m1 * eth / rho
!
      case default
        call fatal_error("eoscalc_farray",'Thermodynamic variable combination not implemented!')
      endselect
!
      if (present(yH)) yH=impossible
!
      if (present(kapparho)) then
        kapparho=0
        call fatal_error("eoscalc","sorry, no Hminus opacity with noionization")
      endif
!
    endsubroutine eoscalc_farray
!***********************************************************************
    subroutine eoscalc_point(ivars,var1,var2,iz,lnrho,ss,yH,lnTT,ee,pp,cs2)
!
!   Calculate thermodynamical quantities
!
!    2-feb-03/axel: simple example coded
!   13-jun-03/tobi: the ionization fraction as part of the f-array
!                   now needs to be given as an argument as input
!   17-nov-03/tobi: moved calculation of cs2 and cp1 to
!                   subroutine pressure_gradient
!   27-mar-06/tony: Introduces cv, cv1, gamma1 to make faster
!                   + more explicit
!   31-mar-06/tony: I removed messy lcalc_cp stuff completely. cp=1.
!                   is just fine.
!   22-jun-06/axel: reinstated cp,cp1,cv,cv1 in hopefully all the places.
!
!   Reference state not yet considered here 
!
      integer, intent(in) :: ivars
      integer, intent(in), optional :: iz
      real, intent(in) :: var1,var2
      real, intent(out), optional :: lnrho,ss
      real, intent(out), optional :: yH,lnTT
      real, intent(out), optional :: ee,pp,cs2
      real :: lnrho_,ss_,lnTT_,ee_,pp_,cs2_,TT_
!
      real :: rho, eth
!
      if (gamma_m1==0.and..not.lanelastic) call fatal_error &
        ('eoscalc_point','gamma=1 not allowed w/entropy')
!
      select case (ivars)
!
      case (ilnrho_ss,irho_ss)
        stratz1: if (lstratz) then
          if (present(iz)) then
            lnrho_ = log(rho0z(iz)) + log(1.0 + var1)
          else
            call fatal_error('eoscalc_point', 'lstratz = .true. requires the optional argument iz. ')
          endif
        elseif (ivars == ilnrho_ss) then stratz1
          lnrho_ = var1
        else stratz1
          lnrho_ = log(var1)
        endif stratz1
        ss_=var2
        lnTT_=lnTT0+cv1*ss_+gamma_m1*(lnrho_-lnrho0)
        ee_=cv*exp(lnTT_)
        pp_=(cp-cv)*exp(lnTT_+lnrho_)
        cs2_=gamma*gamma_m1*ee_
!
      case (ilnrho_ee)
        lnrho_=var1
        ee_=var2
        lnTT_=log(cv1*ee_)
        ss_=cv*(lnTT_-lnTT0-gamma_m1*(lnrho_-lnrho0))
        pp_=gamma_m1*ee_*exp(lnrho_)
        cs2_=gamma*gamma_m1*ee_
!
      case (ilnrho_pp)
        lnrho_=var1
        pp_=var2
        ss_=cv*(log(pp_*exp(-lnrho_)*gamma/cs20)-gamma_m1*(lnrho_-lnrho0))
        ee_=pp_*exp(-lnrho_)/gamma_m1
        lnTT_=log(cv1*ee_)
        cs2_=gamma*gamma_m1*ee_
!
      case (ilnrho_lnTT)
        lnrho_=var1
        lnTT_=var2
        ss_=cv*(lnTT_-lnTT0-gamma_m1*(lnrho_-lnrho0))
        ee_=cv*exp(lnTT_)
        pp_=ee_*exp(lnrho_)*gamma_m1
        cs2_=gamma*gamma_m1*ee_
!
      case (ilnrho_TT)
        lnrho_=var1
        TT_=var2
        ss_=cv*(log(TT_)-lnTT0-gamma_m1*(lnrho_-lnrho0))
        ee_=cv*TT_
        pp_=ee_*exp(lnrho_)*gamma_m1
        cs2_=cp*gamma_m1*TT_
!
      case (irho_TT)
        lnrho_=log(var1)
        TT_=var2
        ss_=cv*(log(TT_)-lnTT0-gamma_m1*(lnrho_-lnrho0))
        ee_=cv*TT_
        pp_=ee_*var1*gamma_m1
        cs2_=cp*gamma_m1*TT_
!
      case (ipp_cs2)
        if (lanelastic) then
          if (lanelastic_lin) then
            lnrho_=log(var1)
            TT_=exp(lnTT0)
            pp_=exp(lnrho_)*cs20/gamma
          else
            if (leos_isothermal) then
              pp_=var1
              lnrho_=log(pp_*cs20)
              TT_=exp(lnTT0)
            endif
          endif
        endif
!
      case (ipp_ss)
        if (lanelastic) then
          if (lanelastic_lin) then
            lnrho_=(var1)
            ss_=var2
            cs2_=exp(gamma*ss_*cp1+gamma_m1*(lnrho_-lnrho0))*cs20
            TT_=cs2_/(gamma_m1*cp)
          else
            pp_=var1
            ss_=var2
            cs2_=exp(ss_*cp1+gamma1*gamma_m1*log(pp_/pp0))*cs20
            TT_=cs2_/(gamma_m1*cp)
            lnrho_=log(gamma*pp_/cs2_)
          endif
        endif
!
      case (irho_eth, ilnrho_eth)
        strat: if (lstratz) then
          chkiz: if (present(iz)) then
            rho = rho0z(iz) * (1.0 + var1)
            eth = eth0z(iz) * (1.0 + var2)
            if (present(lnrho)) lnrho_ = log(rho0z(iz)) + log(1.0 + var1)
          else chkiz
            call fatal_error('eoscalc_point', 'lstratz = .true. requires the optional argument iz. ')
          endif chkiz
        else strat
          if (ldensity_nolog) then
            rho = var1
            if (present(lnrho)) lnrho_ = log(var1)
          else
            rho = exp(var1)
            if (present(lnrho)) lnrho_ = var1
          endif
          eth = var2
        endif strat
        if (present(lnTT)) lnTT_ = log(cv1 * eth / rho)
        if (present(ee)) ee_ = eth / rho
        if (present(pp)) pp_ = gamma_m1 * eth
        if (present(cs2)) cs2_ = gamma * gamma_m1 * eth / rho
        if (present(ss)) call fatal_error('eoscalc_point', 'ss is not implemented for irho_eth')
        if (present(yH)) call fatal_error('eoscalc_point', 'yH is not implemented for irho_eth')
!
      case default
        call not_implemented('eoscalc_point')
      end select
!
      if (present(lnrho)) lnrho=lnrho_
      if (present(ss)) ss=ss_
      if (present(yH)) yH=impossible
      if (present(lnTT)) lnTT=lnTT_
      if (present(ee)) ee=ee_
      if (present(pp)) pp=pp_
      if (present(cs2)) cs2=cs2_
!
    endsubroutine eoscalc_point
!***********************************************************************
    subroutine eoscalc_pencil(ivars,var1,var2,iz,lnrho,ss,yH,lnTT,ee,pp,cs2)
!
!   Calculate thermodynamical quantities
!
!   2-feb-03/axel: simple example coded
!   13-jun-03/tobi: the ionization fraction as part of the f-array
!                   now needs to be given as an argument as input
!   17-nov-03/tobi: moved calculation of cs2 and cp1 to
!                   subroutine pressure_gradient
!   27-mar-06/tony: Introduces cv, cv1, gamma1 to make faster
!                   + more explicit
!   31-mar-06/tony: I removed messy lcalc_cp stuff completely. cp=1.
!                   is just fine.
!   22-jun-06/axel: reinstated cp,cp1,cv,cv1 in hopefully all the places.
!
!   Reference state not yet considered here 
!
      integer, intent(in) :: ivars
      integer, intent(in), optional :: iz
      real, dimension(nx), intent(in) :: var1,var2
      real, dimension(nx), intent(out), optional :: lnrho,ss
      real, dimension(nx), intent(out), optional :: yH,lnTT
      real, dimension(nx), intent(out), optional :: ee,pp,cs2
      real, dimension(nx) :: lnrho_,ss_,lnTT_,ee_,pp_,cs2_,TT_
!
      real, dimension(nx) :: rho, eth
!
      if (gamma_m1==0.) call fatal_error('eoscalc_pencil','gamma=1 not allowed w/entropy')
!
      select case (ivars)
!
      case (ilnrho_ss,irho_ss)
        stratz1: if (lstratz) then
          if (present(iz)) then
            lnrho_ = log(rho0z(iz)) + log(1.0 + var1)
          else
            call fatal_error('eoscalc_pencil', 'lstratz = .true. requires the optional argument iz. ')
          endif
        elseif (ivars == ilnrho_ss) then stratz1
          lnrho_ = var1
        else stratz1
          lnrho_ = log(var1)
        endif stratz1
        ss_=var2
        lnTT_=lnTT0+cv1*ss_+gamma_m1*(lnrho_-lnrho0)
        ee_=cv*exp(lnTT_)
        pp_=(cp-cv)*exp(lnTT_+lnrho_)
        cs2_=gamma*gamma_m1*ee_
        cs2_=cs20*cv1*ee_
!
      case (ilnrho_ee)
        lnrho_=var1
        ee_=var2
        lnTT_=log(cv1*ee_)
        ss_=cv*(lnTT_-lnTT0-gamma_m1*(lnrho_-lnrho0))
        pp_=gamma_m1*ee_*exp(lnrho_)
        cs2_=gamma*gamma_m1*ee_
!
      case (ilnrho_pp)
        lnrho_=var1
        pp_=var2
        ss_=cv*(log(pp_*exp(-lnrho_)*gamma/cs20)-gamma_m1*(lnrho_-lnrho0))
        ee_=pp_*exp(-lnrho_)/gamma_m1
        lnTT_=log(cv1*ee_)
        cs2_=gamma*gamma_m1*ee_
!
      case (ilnrho_lnTT)
        lnrho_=var1
        lnTT_=var2
        ss_=cv*(lnTT_-lnTT0-gamma_m1*(lnrho_-lnrho0))
        ee_=cv*exp(lnTT_)
        pp_=ee_*exp(lnrho_)*gamma_m1
        cs2_=gamma*gamma_m1*ee_
!
      case (ilnrho_TT)
        lnrho_=var1
        TT_=var2
        ss_=cv*(log(TT_)-lnTT0-gamma_m1*(lnrho_-lnrho0))
        ee_=cv*TT_
        pp_=ee_*exp(lnrho_)*gamma_m1
        cs2_=cp*gamma_m1*TT_
!
      case (irho_TT)
        lnrho_=log(var1)
        TT_=var2
        ss_=cv*(log(TT_)-lnTT0-gamma_m1*(lnrho_-lnrho0))
        ee_=cv*TT_
        pp_=ee_*var1*gamma_m1
        cs2_=cp*gamma_m1*TT_
!DM+PC
      case (ipp_ss)
        pp_=var1
        ss_=var2
        lnrho_=log(pp_)/gamma-ss_/cp
        TT_=pp_/((gamma_m1)*cv*exp(lnrho_))
        cs2_=cp*gamma_m1*TT_
!
      case (irho_eth, ilnrho_eth)
        strat: if (lstratz) then
          chkiz: if (present(iz)) then
            rho = rho0z(iz) * (1.0 + var1)
            eth = eth0z(iz) * (1.0 + var2)
            if (present(lnrho)) lnrho_ = log(rho0z(iz)) + log(1.0 + var1)
          else chkiz
            call fatal_error('eoscalc_point', 'lstratz = .true. requires the optional argument iz. ')
          endif chkiz
        else strat
          if (ldensity_nolog) then
            rho = var1
            if (present(lnrho)) lnrho_ = log(var1)
          else
            rho = exp(var1)
            if (present(lnrho)) lnrho_ = var1
          endif
          eth = var2
        endif strat
        if (present(lnTT)) lnTT_ = log(cv1 * eth / rho)
        if (present(ee)) ee_ = eth / rho
        if (present(pp)) pp_ = gamma_m1 * eth
        if (present(cs2)) cs2_ = gamma * gamma_m1 * eth / rho
        if (present(ss)) call fatal_error('eoscalc_pencil', 'ss is not implemented for irho_eth')
        if (present(yH)) call fatal_error('eoscalc_pencil', 'yH is not implemented for irho_eth')
!
      case default
        call not_implemented('eoscalc_pencil')
      end select
!
      if (present(lnrho)) lnrho=lnrho_
      if (present(ss)) ss=ss_
      if (present(yH)) yH=impossible
      if (present(lnTT)) lnTT=lnTT_
      if (present(ee)) ee=ee_
      if (present(pp)) pp=pp_
      if (present(cs2)) cs2=cs2_
!
    endsubroutine eoscalc_pencil
!***********************************************************************
    elemental subroutine get_soundspeed(TT,cs2)
!
!  Calculate sound speed for given temperature
!
!  20-Oct-03/tobi: Coded
!
      real, intent(in)  :: TT
      real, intent(out) :: cs2
!
      cs2=gamma_m1*cp*TT
!
    endsubroutine get_soundspeed
!***********************************************************************
    subroutine read_eos_init_pars(unit,iostat)
!
      include 'unit.h'
      integer, intent(inout), optional :: iostat
!
      if (present(iostat)) then
        read(unit,NML=eos_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=eos_init_pars,ERR=99)
      endif
!
99    return
!
    endsubroutine read_eos_init_pars
!***********************************************************************
    subroutine write_eos_init_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit,NML=eos_init_pars)
!
    endsubroutine write_eos_init_pars
!***********************************************************************
    subroutine read_eos_run_pars(unit,iostat)
!
      include 'unit.h'
      integer, intent(inout), optional :: iostat
!
      if (present(iostat)) then
        read(unit,NML=eos_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=eos_run_pars,ERR=99)
      endif
!
99    return
!
    endsubroutine read_eos_run_pars
!***********************************************************************
    subroutine write_eos_run_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit,NML=eos_run_pars)
!
    endsubroutine write_eos_run_pars
!***********************************************************************
    subroutine isothermal_entropy(f,T0)
!
!  Isothermal stratification (for lnrho and ss)
!  This routine should be independent of the gravity module used.
!  When entropy is present, this module also initializes entropy.
!
!  Sound speed (and hence Temperature), is
!  initialised to the reference value:
!           sound speed: cs^2_0            from start.in
!           density: rho0 = exp(lnrho0)
!
!  11-jun-03/tony: extracted from isothermal routine in Density module
!                  to allow isothermal condition for arbitrary density
!  17-oct-03/nils: works also with leos_ionization=T
!  18-oct-03/tobi: distributed across ionization modules
!  20-jan-15/MR: changes for use of reference state
!
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho
!
      real, dimension(mx,my,mz,mfarray), intent(inout) :: f
      real, intent(in) :: T0
!
      real, dimension(nx) :: lnrho,ss,lnTT
      real, dimension(:,:), pointer :: reference_state
!
!      real :: ss_offset=0.
!
!  if T0 is different from unity, we interpret
!  ss_offset = ln(T0)/gamma as an additive offset of ss
!
!      if (T0/=1.) ss_offset=log(T0)/gamma
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='isothermal_entropy')
!
      do n=n1,n2
      do m=m1,m2
        call getlnrho(f(:,m,n,ilnrho),lnrho)
        lnTT=log(T0)
          !+ other terms for sound speed not equal to cs_0
        call eoscalc(ilnrho_lnTT,lnrho,lnTT,ss=ss)
        if (lreference_state) then 
          f(l1:l2,m,n,iss) = ss - reference_state(:,iref_s)
        else
          f(l1:l2,m,n,iss) = ss
        endif
      enddo
      enddo
!
!  cs2 values at top and bottom may be needed to boundary conditions.
!  The values calculated here may be revised in the entropy module.
!
      call get_soundspeed(T0,cs2bot)
      cs2top=cs2bot
!
    endsubroutine isothermal_entropy
!***********************************************************************
    subroutine isothermal_lnrho_ss(f,T0,rho0)
!
!  Isothermal stratification for lnrho and ss (for yH=0!)
!
!  Currently only implemented for ionization_fixed.
!
      real, dimension(mx,my,mz,mfarray), intent(inout) :: f
      real, intent(in) :: T0,rho0
!
      call keep_compiler_quiet(f)
      call keep_compiler_quiet(T0)
      call keep_compiler_quiet(rho0)
!
    endsubroutine isothermal_lnrho_ss
!***********************************************************************
    subroutine Hminus_opacity(f,kapparho)
!
!  dummy routine
!
!  03-apr-2004/tobi: coded
!
      real, dimension(mx,my,mz,mfarray), intent(in) :: f
      real, dimension(mx,my,mz), intent(out) :: kapparho
!
      call fatal_error('Hminus_opacity',"opacity_type='Hminus' may not be used with noionization")
!
      call keep_compiler_quiet(kapparho)
      call keep_compiler_quiet(f)
!
    endsubroutine Hminus_opacity
!***********************************************************************
    subroutine get_average_pressure(init_average_density,average_density,&
                                    average_pressure)
!
!   01-dec-2009/piyali+dhruba: coded
!
      real, intent(in) :: init_average_density,average_density
      real, intent(inout) :: average_pressure
!
      if (leos_isothermal.or.lfirst) then
        average_pressure = average_density*cs20
      else
        average_pressure = average_pressure+((average_density/&
                           init_average_density)**gamma-1.0)*pp0*pres_corr
        call fatal_error('get_average_pressure','Non isothermal case no coded yet')
      endif
!
    endsubroutine get_average_pressure
!***********************************************************************
    subroutine bdry_magnetic(f,quench,task)
!
!  Calculate magnetic properties needed for z boundary conditions.
!  This routine contains calls to more specialized routines.
!
!   8-jun-13/axel: coded, originally in magnetic, but cyclic dependence
!  21-jan-15/MR  : changes for use of reference state.
!
      use Sub, only: curl, dot2
      use DensityMethods, only: getrho
      use SharedVariables, only: get_shared_variable
      use Mpicomm, only: stop_it
      !use Boundcond, only: boundconds_x, boundconds_y, boundconds_z
      !use Mpicomm, only: initiate_isendrcv_bdry, finalize_isendrcv_bdry
      !use Magnetic_meanfield, only: meanfield_chitB
!
      real, dimension (mx,my,mz,mfarray), intent (in) :: f
      real, dimension (nx,3) :: bb
      real, dimension (nx) :: rho,b2,quench
      character (len=*), intent(in) :: task
      integer :: j
!
      !character (len=linelen), pointer :: dummy
      integer :: ierr
!
      if (lrun .and. lmagn_mf) then
        !call get_shared_variable('meanfield_Beq_profile',dummy,ierr)
        !if (ierr/=0) call stop_it("meanfield_Beq_profile: "//&
        !     "there was a problem when getting meanfield_Beq_profile")
        !meanfield_Beq_profile=dummy
        call get_shared_variable('meanfield_Beq',meanfield_Beq,ierr)
        if (ierr/=0) call stop_it("meanfield_Beq: "//&
             "there was a problem when getting meanfield_Beq")
        call get_shared_variable('chit_quenching',chit_quenching,ierr)
        if (ierr/=0) call stop_it("chit_quenching: "//&
             "there was a problem when getting chit_quenching")
        call get_shared_variable('uturb',uturb,ierr)
        if (ierr/=0) call stop_it("uturb: "//&
             "there was a problem when getting uturb")
        call get_shared_variable('B_ext',B_ext,caller='bdry_magnetic')
      endif
!
      select case (task)
!
      case ('meanfield_chitB')
!
        !call boundconds_x(f,iax,iaz)
        !call initiate_isendrcv_bdry(f,iax,iaz)
        !call finalize_isendrcv_bdry(f,iax,iaz)
        !call boundconds_y(f,iax,iaz)
        !call boundconds_z(f,iax,iaz)
!
!  Add the external field.
!
        call curl(f,iaa,bb)
        do j=1,3
          bb(:,j)=bb(:,j)!+B_ext(j)
        enddo
        call dot2(bb,b2)
        call getrho(f(:,m,n,ilnrho),rho)
!
!  Call mean-field routine.
!
        call meanfield_chitB(rho,b2,quench)
!
!  capture undefined entries
!
      case default
        call fatal_error('bdry_magnetic','invalid argument')
      endselect
!
    endsubroutine bdry_magnetic
!***********************************************************************
    subroutine meanfield_chitB(rho,b2,quench)
!
!  Calculate magnetic properties needed for z boundary conditions.
!  This routine contails calls to more specialized routines.
!
!   8-jun-13/axel: coded
!
      real, dimension (nx) :: rho,b2,Beq21,quench
!
!  compute Beq21 = 1/Beq^2
!XX
!     select case (meanfield_Beq_profile)
!     case ('uturbconst');
        Beq21=mu01/(rho*uturb**2)
!     case default;
!       Beq21=1./meanfield_Beq**2
!     endselect
!
!  compute chit_quenching
!
      quench=1./(1.+chit_quenching*b2*Beq21)
!
    endsubroutine meanfield_chitB
!***********************************************************************
    subroutine bc_ss_flux(f,topbot)
!
!  constant flux boundary condition for entropy (called when bcz='c1')
!
!  23-jan-2002/wolf: coded
!  11-jun-2002/axel: moved into the entropy module
!   8-jul-2002/axel: split old bc_ss into two
!  26-aug-2003/tony: distributed across ionization modules
!  13-mar-2011/pete: c1 condition for z-boundaries with Kramers' opacity
!
      use Mpicomm, only: stop_it
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getrho, getdlnrho
!
      real, pointer :: Fbot,Ftop,FtopKtop,FbotKbot,hcond0,hcond1,chi
      real, pointer :: hcond0_kramers, nkramers
      logical, pointer :: lmultilayer, lheatc_chiconst, lheatc_kramers
      real, dimension(:,:), pointer :: reference_state
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my) :: tmp_xy,cs2_xy,rho_xy
      integer :: i,ierr
!
      if (ldebug) print*,'bc_ss_flux: ENTER - cs20,cs0=',cs20,cs0
!
!  Do the `c1' boundary condition (constant heat flux) for entropy.
!  check whether we want to do top or bottom (this is precessor dependent)
!
!  Get the shared variables
!
      call get_shared_variable('hcond0',hcond0,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting hcond0")
      call get_shared_variable('hcond1',hcond1,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting hcond1")
      call get_shared_variable('Fbot',Fbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting Fbot")
      call get_shared_variable('Ftop',Ftop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting Ftop")
      call get_shared_variable('FbotKbot',FbotKbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting FbotKbot")
      call get_shared_variable('FtopKtop',FtopKtop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting FtopKtop")
      call get_shared_variable('chi',chi,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting chi")
      call get_shared_variable('lmultilayer',lmultilayer,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting lmultilayer")
      call get_shared_variable('lheatc_chiconst',lheatc_chiconst,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting lheatc_chiconst")
      call get_shared_variable('hcond0_kramers',hcond0_kramers,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting hcond0_kramers")
      call get_shared_variable('nkramers',nkramers,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting nkramers")
      call get_shared_variable('lheatc_kramers',lheatc_kramers,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux: "//&
           "there was a problem when getting lheatc_kramers")
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='bc_ss_flux')
!
      select case (topbot)
!
!  bottom boundary
!  ===============
!
      case ('bot')
        if (lmultilayer) then
          if (headtt) print*,'bc_ss_flux: Fbot,hcond=',Fbot,hcond0*hcond1
        else
          if (headtt) print*,'bc_ss_flux: Fbot,hcond=',Fbot,hcond0
        endif
!
!  calculate Fbot/(K*cs2)
!
        if (pretend_lnTT) then
          tmp_xy=-FbotKbot/exp(f(:,:,n1,iss))
          do i=1,nghost
            f(:,:,n1-i,iss)=f(:,:,n1+i,iss)-dz2_bound(-i)*tmp_xy
          enddo
        else
!
          call getrho(f(:,:,n1,ilnrho),rho_xy)
!
          if (ldensity_nolog) then
            cs2_xy = f(:,:,n1,iss)
            if (lreference_state) &
              cs2_xy(l1:l2,:) = cs2_xy(l1:l2,:) + transpose(spread(reference_state(:,iref_s),1,my))
            cs2_xy=cs20*exp(gamma_m1*(log(rho_xy)-lnrho0)+cv1*cs2_xy)
          else
            cs2_xy=cs20*exp(gamma_m1*(f(:,:,n1,ilnrho)-lnrho0)+cv1*f(:,:,n1,iss))
          endif
!
!  Check whether we have chi=constant at bottom, in which case
!  we have the nonconstant rho_xy*chi in tmp_xy.
!  Check also whether Kramers opacity is used, then hcond itself depends
!  on density and temperature.
!
          if (lheatc_chiconst) then
            tmp_xy=Fbot/(rho_xy*chi*cs2_xy)
          else if (lheatc_kramers) then
            tmp_xy=Fbot*rho_xy**(2*nkramers)*(cp*gamma_m1)**(6.5*nkramers) &
                   /(hcond0_kramers*cs2_xy**(6.5*nkramers+1.))
          else
            tmp_xy=FbotKbot/cs2_xy
          endif
!
!  enforce ds/dz + gamma_m1/gamma*dlnrho/dz = - gamma_m1/gamma*Fbot/(K*cs2)
!
          do i=1,nghost
            call getdlnrho(f(:,:,n1-i:n1+i,ilnrho),i,rho_xy)                     ! rho_xy=d ln(rho)
            f(:,:,n1-i,iss)=f(:,:,n1+i,iss)+(cp-cv)*(rho_xy+dz2_bound(-i)*tmp_xy)
            if (lreference_state) &
              f(:,:,n1-i,iss)=f(:,:,n1-i,iss) + dz2_bound(-i)*transpose(spread(reference_state(:,iref_gs),1,my))
          enddo
        endif
!
!  top boundary
!  ============
!
      case ('top')
!
!  calculate Fbot/(K*cs2)
!
        if (pretend_lnTT) then
          tmp_xy=-FtopKtop/exp(f(:,:,n2,iss))
          do i=1,nghost
             f(:,:,n2-i,iss)=f(:,:,n2+i,iss)-dz2_bound(i)*tmp_xy
          enddo
        else
!
          call getrho(f(:,:,n2,ilnrho),rho_xy)
          if (ldensity_nolog) then
            cs2_xy = f(:,:,n2,iss)		! here cs2_xy = ss
            if (lreference_state) &
              cs2_xy = cs2_xy + transpose(spread(reference_state(:,iref_s),1,my))
            cs2_xy=cs20*exp(gamma_m1*(log(rho_xy)-lnrho0)+cv1*cs2_xy)
          else
            cs2_xy=cs20*exp(gamma_m1*(f(:,:,n2,ilnrho)-lnrho0)+cv1*f(:,:,n2,iss))
          endif
!
!  Check whether we have chi=constant at top, in which case
!  we have the nonconstant rho_xy*chi in tmp_xy.
!  Check also whether Kramers opacity is used, then hcond itself depends
!  on density and temperature.
!
          if (lheatc_chiconst) then
            tmp_xy=Ftop/(rho_xy*chi*cs2_xy)
          else if (lheatc_kramers) then
            tmp_xy=Ftop*rho_xy**(2*nkramers)*(cp*gamma_m1)**(6.5*nkramers) &
                   /(hcond0_kramers*cs2_xy**(6.5*nkramers+1.))
          else
            tmp_xy=FtopKtop/cs2_xy
          endif
!
!  enforce ds/dz + gamma_m1/gamma*dlnrho/dz = - gamma_m1/gamma*Fbot/(K*cs2)
!
          do i=1,nghost
            call getdlnrho(f(:,:,n2-i:n2+i,ilnrho),i,rho_xy)  ! rho_xy=d ln(rho)
            f(:,:,n2+i,iss)=f(:,:,n2-i,iss)+(cp-cv)*(-rho_xy-dz2_bound(i)*tmp_xy)
            if (lreference_state) &
              f(:,:,n2+i,iss)=f(:,:,n2+i,iss) - dz2_bound(i)*transpose(spread(reference_state(:,iref_gs),1,my))
          enddo
        endif
!
      case default
        call fatal_error('bc_ss_flux','invalid argument')
      endselect
!
    endsubroutine bc_ss_flux
!***********************************************************************
    subroutine bc_ss_flux_turb(f,topbot)
!
!  Black body boundary condition for entropy (called when bcz='Fgs')
!  setting F = sigmaSBt*T^4 where sigmaSBt is related to the
!  Stefan-Boltzmann constant.
!
!   04-may-2009/axel: adapted from bc_ss_flux
!   31-may-2010/pete: replaced sigmaSB by a `turbulent' sigmaSBt
!
      use Mpicomm, only: stop_it
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho, getrho
!
      logical, pointer :: lmeanfield_chitB
      real, pointer :: chi,chi_t,chi_t0,hcondzbot,hcondztop,chit_prof1,chit_prof2
      real, dimension(:,:), pointer :: reference_state
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my) :: dsdz_xy,cs2_xy,rho_xy,TT_xy,dlnrhodz_xy,chi_xy
      real, dimension (nx) :: quench
      real :: fac
      integer :: i,ierr
!
      if (ldebug) print*,'bc_ss_flux_turb: ENTER - cs20,cs0=',cs20,cs0
!
!  Get the shared variables for magnetic quenching effect in a
!  mean-field description of a radiative boundary condition.
!  Ideally, one would like this to reside in magnetic/meanfield,
!  but this leads currently to circular dependencies.
!
      call get_shared_variable('chi_t',chi_t,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb: "//&
           "there was a problem when getting chi_t")
      call get_shared_variable('chit_prof1',chit_prof1,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb_x: "//&
           "there was a problem when getting chit_prof1")
      call get_shared_variable('chit_prof2',chit_prof2,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb_x: "//&
           "there was a problem when getting chit_prof2")
      call get_shared_variable('chi',chi,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb: "//&
           "there was a problem when getting chi")
      call get_shared_variable('hcondzbot',hcondzbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb: "//&
           "there was a problem when getting hcondzbot")
      call get_shared_variable('hcondztop',hcondztop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb: "//&
           "there was a problem when getting hcondztop")
!
!  lmeanfield_chitB and chi_t0
!
      if (lmagnetic) then
        call get_shared_variable('lmeanfield_chitB',lmeanfield_chitB,ierr)
        if (ierr/=0) call stop_it("bc_ss_flux_turb: "//&
             "there was a problem when getting lmeanfield_chitB")
        if (lmeanfield_chitB) then
          call get_shared_variable('chi_t0',chi_t0,ierr)
          if (ierr/=0) call stop_it("bc_ss_flux_turb: "//&
               "there was a problem when getting chi_t0")
        else
          lmeanfield_chitB=.false.
        endif
      endif
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='bc_ss_flux_turb')
!
      select case (topbot)
!
!  Check whether we want to do top or bottom (this is precessor dependent)
!
!  bottom boundary
!  ===============
!
      case ('bot')
!
!  set ghost zones such that dsdz_xy obeys
!  - chi_t rho T dsdz_xy - hcond gTT = sigmaSBt*TT^4
!
        call getlnrho(f(:,:,n1,ilnrho),rho_xy)      ! here rho_xy=log(rho)
        cs2_xy=gamma_m1*(rho_xy-lnrho0)+cv1*f(:,:,n1,iss)
        if (lreference_state) &
          cs2_xy=cs2_xy+cv1*transpose(spread(reference_state(:,iref_s),1,my))
        cs2_xy=cs20*exp(cs2_xy)

        call getrho(f(:,:,n1,ilnrho),rho_xy)
        TT_xy=cs2_xy/(gamma_m1*cp)
!
        fac=(1./60)*dz_1(n1)
        dlnrhodz_xy=fac*(+ 45.0*(f(:,:,n1+1,ilnrho)-f(:,:,n1-1,ilnrho)) &
                         -  9.0*(f(:,:,n1+2,ilnrho)-f(:,:,n1-2,ilnrho)) &
                         +      (f(:,:,n1+3,ilnrho)-f(:,:,n1-3,ilnrho)))
        dsdz_xy=-(sigmaSBt*TT_xy**3+hcondzbot*(gamma_m1)*dlnrhodz_xy)/ &
            (chit_prof1*chi_t*rho_xy+hcondzbot/cv)
!
!  enforce ds/dz=-(sigmaSBt*T^3 + hcond*(gamma-1)*glnrho)/(chi_t*rho+hcond/cv)
!
        do i=1,nghost
          f(:,:,n1-i,iss)=f(:,:,n1+i,iss)+dz2_bound(-i)*dsdz_xy
          if (lreference_state) f(:,:,n1-i,iss)=f(:,:,n1-i,iss)   !!!+spread(dz2_bound(-i)*reference_state(:,iref_gs),1,my)
        enddo
!
!  top boundary
!  ============
!
      case ('top')
!
!  set ghost zones such that dsdz_xy obeys
!  - chi_t rho T dsdz_xy - hcond gTT = sigmaSBt*TT^4
!
        call getlnrho(f(:,:,n2,ilnrho),rho_xy)      ! here rho_xy=log(rho)
        cs2_xy=gamma_m1*(rho_xy-lnrho0)+cv1*f(:,:,n2,iss)
        if (lreference_state) &
          cs2_xy=cs2_xy + cv1*transpose(spread(reference_state(:,iref_s),1,my))
        cs2_xy=cs20*exp(cs2_xy)

        call getrho(f(:,:,n2,ilnrho),rho_xy)
        TT_xy=cs2_xy/(gamma_m1*cp)

        fac=(1./60)*dz_1(n2)
        dlnrhodz_xy=fac*(+ 45.0*(f(:,:,n2+1,ilnrho)-f(:,:,n2-1,ilnrho)) &
                         -  9.0*(f(:,:,n2+2,ilnrho)-f(:,:,n2-2,ilnrho)) &
                         +      (f(:,:,n2+3,ilnrho)-f(:,:,n2-3,ilnrho)))
!
!  Set chi_xy=chi, which sets also the ghost zones.
!  chi_xy consists of molecular and possibly turbulent values.
!  The turbulent value can be quenched (but not in ghost zones).
!
      chi_xy=chi
      if (lmagnetic) then
        if (lmeanfield_chitB) then
          n=n2
          do m=m1,m2
            call bdry_magnetic(f,quench,'meanfield_chitB')
          enddo
          chi_xy(l1:l2,m)=chi+chi_t0*quench
        endif
      endif
!
!  Select to use either sigmaSBt*TT^4 = - K dT/dz - chi_t*rho*T*ds/dz,
!      or: sigmaSBt*TT^4 = - chi_xy*rho*cp dT/dz - chi_t*rho*T*ds/dz.
!
        if (hcondztop==impossible) then
          dsdz_xy=-(sigmaSBt*TT_xy**3+chi_xy*rho_xy*cp*(gamma_m1)*dlnrhodz_xy)/ &
              (chit_prof2*chi_t*rho_xy+chi_xy*rho_xy*cp/cv)
        else
          dsdz_xy=-(sigmaSBt*TT_xy**3+hcondztop*(gamma_m1)*dlnrhodz_xy)/ &
              (chit_prof2*chi_t*rho_xy+hcondztop/cv)
        endif
!
!  Apply condition;
!  enforce ds/dz=-(sigmaSBt*T^3 + hcond*(gamma-1)*glnrho)/(chi_t*rho+hcond/cv)
!
        do i=1,nghost
          f(:,:,n2+i,iss)=f(:,:,n2-i,iss)+dz2_bound(i)*dsdz_xy
          if (lreference_state) f(:,:,n2-i,iss)=f(:,:,n2-i,iss)   !!!+spread(dz2_bound(i)*reference_state(:,iref_gs),1,my)
        enddo
!
!  capture undefined entries
!
      case default
        call fatal_error('bc_ss_flux_turb','invalid argument')
      endselect
!
    endsubroutine bc_ss_flux_turb
!***********************************************************************
    subroutine bc_ss_flux_turb_x(f,topbot)
!
!  Black body boundary condition for entropy (called when bcx='Fgs')
!  setting F = sigmaSBt*T^4 where sigmaSBt is related to the
!  Stefan-Boltzmann constant.
!
!   31-may-2010/pete: adapted from bc_ss_flux_turb
!   20-jul-2010/pete: expanded to take into account hcond/=0
!   21-jan-2015/MR: changes for reference state.
!   22-jan-2015/MR: corrected bug in branches for pretend_lnTT=T
!
      use Mpicomm, only: stop_it
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getrho
!
      real, pointer :: chi_t,hcondxbot,hcondxtop,chit_prof1,chit_prof2
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (my,mz) :: dsdx_yz,cs2_yz,rho_yz,dlnrhodx_yz,TT_yz
      real :: fac
      integer :: i,ierr
      real, dimension(:,:), pointer :: reference_state
!
      if (ldebug) print*,'bc_ss_flux_turb: ENTER - cs20,cs0=',cs20,cs0
!
!  Get the shared variables
!
      call get_shared_variable('chi_t',chi_t,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb_x: "//&
           "there was a problem when getting chi_t")
      call get_shared_variable('chit_prof1',chit_prof1,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb_x: "//&
           "there was a problem when getting chit_prof1")
      call get_shared_variable('chit_prof2',chit_prof2,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb_x: "//&
           "there was a problem when getting chit_prof2")
      call get_shared_variable('hcondxbot',hcondxbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb_x: "//&
           "there was a problem when getting hcondxbot")
      call get_shared_variable('hcondxtop',hcondxtop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_turb_x: "//&
           "there was a problem when getting hcondxtop")
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='bc_ss_flux_turb_x')
!
      select case (topbot)
!
!  Check whether we want to do top or bottom (this is processor dependent)
!
!  bottom boundary
!  ===============
!
      case ('bot')
!
! For the case of pretend_lnTT=T, set glnTT=-sigma*T^3/hcond
!
        if (pretend_lnTT) then
          do i=1,nghost
            f(l1-i,:,:,iss)=f(l1+i,:,:,iss) + &     ! MR: corrected, plus sign correct? 
                dx2_bound(-i)*sigmaSBt*exp(f(l1,:,:,iss))**3/hcondxbot
          enddo
        else
!
!  set ghost zones such that dsdx_yz obeys
!  - chi_t rho T dsdx_yz - hcond gTT = sigmaSBt*TT^4
!
          call getrho(f(l1,:,:,ilnrho),rho_yz,BOT)

          if (ldensity_nolog) then
            cs2_yz=f(l1,:,:,iss)       ! here cs2_yz = ss
            if (lreference_state) cs2_yz = cs2_yz+reference_state(BOT,iref_s)
            cs2_yz=cs20*exp(gamma_m1*(log(rho_yz)-lnrho0)+cv1*cs2_yz)
          else
            cs2_yz=cs20*exp(gamma_m1*(f(l1,:,:,ilnrho)-lnrho0)+cv1*f(l1,:,:,iss))
          endif
!
          TT_yz=cs2_yz/(gamma_m1*cp)
!
!  Calculate d rho/d x    or   d ln(rho) / dx
!
          fac=(1./60)*dx_1(l1)
          dlnrhodx_yz=fac*(+ 45.0*(f(l1+1,:,:,ilnrho)-f(l1-1,:,:,ilnrho)) &
                           -  9.0*(f(l1+2,:,:,ilnrho)-f(l1-2,:,:,ilnrho)) &
                           +      (f(l1+3,:,:,ilnrho)-f(l1-3,:,:,ilnrho)))
        
          if (ldensity_nolog) then
!
!  Add gradient of reference density and divide by total density
!
            if (lreference_state) then
              dlnrhodx_yz=dlnrhodx_yz + reference_state(BOT,iref_grho)
              dlnrhodx_yz=dlnrhodx_yz/(rho_yz + reference_state(BOT,iref_rho))
            else
              dlnrhodx_yz=dlnrhodx_yz/rho_yz
            endif
!
          endif
!
          dsdx_yz=-(sigmaSBt*TT_yz**3+hcondxbot*(gamma_m1)*dlnrhodx_yz)/ &
                   (chit_prof1*chi_t*rho_yz+hcondxbot/cv)
!
!  Substract gradient of reference entropy.
!
          if (lreference_state) dsdx_yz = dsdx_yz - reference_state(BOT,iref_gs)
!
!  enforce ds/dx = - (sigmaSBt*T^3 + hcond*(gamma-1)*glnrho)/(chi_t*rho+hcond/cv)
!
          do i=1,nghost
            f(l1-i,:,:,iss)=f(l1+i,:,:,iss)-dx2_bound(-i)*dsdx_yz
          enddo
        endif
!
!  top boundary
!  ============
!
      case ('top')
!
!  For the case of pretend_lnTT=T, set glnTT=-sigma*T^3/hcond
!
        if (pretend_lnTT) then
          do i=1,nghost
            f(l2+i,:,:,iss)=f(l2-i,:,:,iss) + &     ! MR: corrected, plus sign correct?
                dx2_bound(i)*sigmaSBt*exp(f(l2,:,:,iss))**3/hcondxtop
          enddo
        else
!
!  set ghost zones such that dsdx_yz obeys
!  - chi_t rho T dsdx_yz - hcond gTT = sigmaSBt*TT^4
!
          call getrho(f(l2,:,:,ilnrho),rho_yz,TOP)

          if (ldensity_nolog) then
            cs2_yz=f(l2,:,:,iss)    ! here entropy
            if (lreference_state) &
              cs2_yz = cs2_yz+reference_state(TOP,iref_s)
            cs2_yz=cs20*exp(gamma_m1*(log(rho_yz)-lnrho0)+cv1*cs2_yz)
          else
            cs2_yz=cs20*exp(gamma_m1*(f(l2,:,:,ilnrho)-lnrho0)+cv1*f(l2,:,:,iss))
          endif
!            
          TT_yz=cs2_yz/(gamma_m1*cp)
!
!  Calculate d rho/d x    or   d ln(rho) / dx
!
          fac=(1./60)*dx_1(l2)
          dlnrhodx_yz=fac*(+ 45.0*(f(l2+1,:,:,ilnrho)-f(l2-1,:,:,ilnrho)) &
                           -  9.0*(f(l2+2,:,:,ilnrho)-f(l2-2,:,:,ilnrho)) &
                           +      (f(l2+3,:,:,ilnrho)-f(l2-3,:,:,ilnrho)))
!
          if (ldensity_nolog) then
!
!  Add gradient of reference density to d rho/d x and divide by total density
!
            if (lreference_state) then
              dlnrhodx_yz=dlnrhodx_yz + reference_state(TOP,iref_grho)
              dlnrhodx_yz=dlnrhodx_yz/(rho_yz + reference_state(TOP,iref_rho))
            else
              dlnrhodx_yz=dlnrhodx_yz/rho_yz
            endif

          endif
!
          dsdx_yz=-(sigmaSBt*TT_yz**3+hcondxtop*(gamma_m1)*dlnrhodx_yz)/ &
                   (chit_prof2*chi_t*rho_yz+hcondxtop/cv)
!
!  Substract gradient of reference entropy.
!
          if (lreference_state) dsdx_yz = dsdx_yz - reference_state(TOP,iref_gs)
!
!  enforce ds/dx = - (sigmaSBt*T^3 + hcond*(gamma-1)*glnrho)/(chi_t*rho+hcond/cv)
!
          do i=1,nghost
            f(l2+i,:,:,iss)=f(l2-i,:,:,iss)+dx2_bound(i)*dsdx_yz
          enddo
        endif
!
!  capture undefined entries
!
      case default
        call fatal_error('bc_ss_flux_turb_x','invalid argument')
      endselect
!
    endsubroutine bc_ss_flux_turb_x
!***********************************************************************
    subroutine bc_ss_flux_condturb_x(f,topbot)
!
!   Constant conductive + turbulent flux through the surface
!
!   08-apr-2014/pete: coded
!   21-jan-2015/MR: changes for reference state.
!
      use Mpicomm, only: stop_it
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getrho,getdlnrho
!
      real, pointer :: chi_t, hcondxbot, hcondxtop, chit_prof1, chit_prof2
      real, pointer :: Fbot, Ftop
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (my,mz) :: dsdx_yz, cs2_yz, rho_yz, dlnrhodx_yz
      real :: fac
      integer :: i,ierr
      real, dimension(:,:), pointer :: reference_state
!
      if (ldebug) print*,'bc_ss_flux_condturb: ENTER - cs20,cs0=',cs20,cs0
!
!  Get the shared variables
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='bc_ss_flux_condturb_x')
!
      call get_shared_variable('chi_t',chi_t,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_x: "//&
           "there was a problem when getting chi_t")
      call get_shared_variable('chit_prof1',chit_prof1,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_x: "//&
           "there was a problem when getting chit_prof1")
      call get_shared_variable('chit_prof2',chit_prof2,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_x: "//&
           "there was a problem when getting chit_prof2")
      call get_shared_variable('hcondxbot',hcondxbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_x: "//&
           "there was a problem when getting hcondxbot")
      call get_shared_variable('hcondxtop',hcondxtop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_x: "//&
           "there was a problem when getting hcondxtop")
      call get_shared_variable('Fbot',Fbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_x: "//&
           "there was a problem when getting Fbot")
      call get_shared_variable('Ftop',Ftop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_x: "//&
           "there was a problem when getting Ftop")
!
      select case (topbot)
!
!  Check whether we want to do top or bottom (this is precessor dependent)
!
!  bottom boundary
!  ===============
!
      case ('bot')
!
! Do the pretend_lnTT=T case first
!
        if (pretend_lnTT) then
           call stop_it("bc_ss_flux_condturb_x: not implemented for pretend_lnTT=T")
        else
!
!  Set ghost zones such that -chi_t*rho*T*grads -hcond*gTT = Fbot
!
          call getrho(f(l1,:,:,ilnrho),rho_yz,BOT)

          if (ldensity_nolog) then
            cs2_yz=f(l1,:,:,iss)      ! here entropy
            if (lreference_state) &
              cs2_yz = cs2_yz+reference_state(BOT,iref_s)
            cs2_yz=cs20*exp(gamma_m1*(log(rho_yz)-lnrho0)+cv1*cs2_yz)
          else
            cs2_yz=cs20*exp(gamma_m1*(f(l1,:,:,ilnrho)-lnrho0)+cv1*f(l1,:,:,iss))
          endif
!
!  The following calculations in fact not needed (?).
!  Calculate d rho/d x   or   d ln(rho)/ d x
!
          fac=(1./60)*dx_1(l1)
          dlnrhodx_yz=fac*(+ 45.0*(f(l1+1,:,:,ilnrho)-f(l1-1,:,:,ilnrho)) &
                           -  9.0*(f(l1+2,:,:,ilnrho)-f(l1-2,:,:,ilnrho)) &
                           +      (f(l1+3,:,:,ilnrho)-f(l1-3,:,:,ilnrho)))
          if (ldensity_nolog) then
!
!  Add gradient of reference density and divide by total density.
!
            if (lreference_state) then
              dlnrhodx_yz=dlnrhodx_yz + reference_state(BOT,iref_grho)
              dlnrhodx_yz=dlnrhodx_yz/(rho_yz + reference_state(BOT,iref_rho))
            else
              dlnrhodx_yz=dlnrhodx_yz/rho_yz
            endif
!
          endif
!
          dsdx_yz=(cp*gamma_m1*Fbot/cs2_yz)/ &
                  (chit_prof1*chi_t*rho_yz + hcondxbot*gamma)
!
!  Substract gradient of reference entropy.
!
          if (lreference_state) dsdx_yz = dsdx_yz - reference_state(BOT,iref_gs)
!
!  Enforce ds/dx = -(cp*gamma_m1*Fbot/cs2 + K*gamma_m1*glnrho)/(gamma*K+chi_t*rho)
!
          do i=1,nghost
            call getdlnrho(f(l1-i:l1+i,:,:,ilnrho),i,dx2_bound(-i),dlnrhodx_yz,BOT)
            f(l1-i,:,:,iss)=f(l1+i,:,:,iss) + &
                (hcondxbot*gamma_m1/(gamma*hcondxbot+chit_prof1*chi_t*rho_yz))* &
                dlnrhodx_yz+dx2_bound(-i)*dsdx_yz
            if (lreference_state) f(l1-i,:,:,iss)=f(l1-i,:,:,iss) + reference_state(BOT,iref_s)
          enddo
        endif
!
!  top boundary
!  ============
!
      case ('top')
!
         call stop_it("bc_ss_flux_condturb_x: not implemented for the top boundary")
!
!  capture undefined entries
!
      case default
        call fatal_error('bc_ss_flux_condturb_x','invalid argument')
      endselect
!
    endsubroutine bc_ss_flux_condturb_x
!***********************************************************************
    subroutine bc_ss_flux_condturb_mean_x(f,topbot)
!
!   Constant conductive + turbulent flux through the surface applied on
!   the spherically symmetric part, zero gradient for the fluctuation
!   at the boundary.
!
!   18-dec-2014/pete: coded
!
      use Mpicomm, only: stop_it, mpiallreduce_sum
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho
!
      real, pointer :: chi_t, hcondxbot, hcondxtop, chit_prof1, chit_prof2
      real, pointer :: Fbot, Ftop
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (my,mz) :: dsdx_yz, dlnrhodx_yz
      real, dimension (mx) :: lnrmx, lnrmx_tmp
      real :: cs2mx, cs2mx_tmp
      real :: fac, fact, dlnrmxdx, tmp1
      real, dimension(ny) :: tmp2
      integer :: i,l,ierr
      real, dimension(:,:), pointer :: reference_state
!
      if (ldebug) print*,'bc_ss_flux_condturb_mean_x: ENTER - cs20,cs0=',cs20,cs0
!
!  Get the shared variables
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='bc_ss_flux_condturb_mean_x')
!
      call get_shared_variable('chi_t',chi_t,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_mean_x: "//&
           "there was a problem when getting chi_t")
      call get_shared_variable('chit_prof1',chit_prof1,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_mean_x: "//&
           "there was a problem when getting chit_prof1")
      call get_shared_variable('chit_prof2',chit_prof2,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_mean_x: "//&
           "there was a problem when getting chit_prof2")
      call get_shared_variable('hcondxbot',hcondxbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_mean_x: "//&
           "there was a problem when getting hcondxbot")
      call get_shared_variable('hcondxtop',hcondxtop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_mean_x: "//&
           "there was a problem when getting hcondxtop")
      call get_shared_variable('Fbot',Fbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_mean_x: "//&
           "there was a problem when getting Fbot")
      call get_shared_variable('Ftop',Ftop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_mean_x: "//&
           "there was a problem when getting Ftop")
!
      select case (topbot)
!
!  Check whether we want to do top or bottom (this is precessor dependent)
!
!  bottom boundary
!  ===============
!
      case ('bot')
!
! Do the pretend_lnTT=T case first
!
        if (pretend_lnTT) then
           call stop_it("bc_ss_flux_condturb_mean_x: not implemented for pretend_lnTT=T")
        else
!
!  Compute yz-averaged log density and sound speed
!
          fact=1./((cos(y0)-cos(y0+Lxyz(2)))*Lxyz(3))
          cs2mx=0.
          do n=n1,n2
            call getlnrho(f(l1,:,n,ilnrho),tmp2,BOT)
            tmp2 = gamma_m1*(tmp2-lnrho0) + cv1*f(l1,m1:m2,n,iss)
            if (lreference_state) tmp2 = tmp2 + cv1*reference_state(BOT,iref_s)
            cs2mx = cs2mx+sum(cs20*exp(tmp2)*dVol_y(m1:m2))*dVol_z(n)
          enddo
          cs2mx=fact*cs2mx
!
          lnrmx=0.
          fact=1./((cos(y0)-cos(y0+Lxyz(2)))*Lxyz(3))
          do l=1,mx
            tmp1=0.
            do n=n1,n2
              call getlnrho(f(l1,:,n,ilnrho),tmp2,BOT)    ! doubled call not yet optimal
              tmp1=tmp1+sum(tmp2*dVol_y(m1:m2))*dVol_z(n)
            enddo
            lnrmx(l)=lnrmx(l)+tmp1
          enddo
          lnrmx=fact*lnrmx
!
!  Communication over all processors in the yz plane.
!
          if (nprocy>1.or.nprocz>1) then
            call mpiallreduce_sum(lnrmx,lnrmx_tmp,mx,idir=23)
            call mpiallreduce_sum(cs2mx,cs2mx_tmp,idir=23)
            lnrmx=lnrmx_tmp
            cs2mx=cs2mx_tmp
          endif
!
          do i=1,nghost; lnrmx(l1-i)=2.*lnrmx(l1)-lnrmx(l1+i); enddo
!
!  Compute x-derivative of mean lnrho
!
          fac=(1./60)*dx_1(l1)
          dlnrmxdx=fac*(+ 45.0*(lnrmx(l1+1)-lnrmx(l1-1)) &
                        -  9.0*(lnrmx(l1+2)-lnrmx(l1-2)) &
                        +      (lnrmx(l1+3)-lnrmx(l1-3)))
!
!  Set ghost zones such that -chi_t*rho*T*grads -hcond*gTT = Fbot, i.e.
!  enforce:
!    ds/dx = -(cp*gamma_m1*Fbot/cs2 + K*gamma_m1*glnrho)/(gamma*K+chi_t*rho)
!
          dsdx_yz=(-cp*gamma_m1*Fbot/cs2mx)/ &
               (chit_prof1*chi_t*exp(lnrmx(l1)) + hcondxbot*gamma) - &
              gamma_m1/gamma*dlnrmxdx
!
          if (lreference_state) &
            dsdx_yz = dsdx_yz - reference_state(BOT,iref_gs)
!
          do i=1,nghost
            f(l1-i,:,:,iss)=f(l1+i,:,:,iss)-dx2_bound(-i)*dsdx_yz
          enddo
        endif
!
!  top boundary
!  ============
!
      case ('top')
!
         call stop_it("bc_ss_flux_condturb_mean_x: not implemented for the top boundary")
!
!  capture undefined entries
!
      case default
        call fatal_error('bc_ss_flux_condturb_mean_x','invalid argument')
      endselect
!
    endsubroutine bc_ss_flux_condturb_mean_x
!***********************************************************************
    subroutine bc_ss_flux_condturb_z(f,topbot)
!
!   Constant conductive + turbulent flux through the surface
!
!   15-jul-2014/pete: adapted from bc_ss_flux_condturb_x
!
      use Mpicomm, only: stop_it
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho, getrho, getdlnrho
!
      real, pointer :: chi, hcondzbot, hcondztop
      real, pointer :: chi_t, chit_prof1, chit_prof2
      real, pointer :: Fbot, Ftop
      logical, pointer :: lheatc_chiconst
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my) :: dsdz_xy, cs2_xy, rho_xy
      real :: fac
      integer :: i,ierr
!
      if (ldebug) print*,'bc_ss_flux_turb: ENTER - cs20,cs0=',cs20,cs0
!
!  Get the shared variables
!
      call get_shared_variable('chi_t',chi_t,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting chi_t")
      call get_shared_variable('chit_prof1',chit_prof1,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting chit_prof1")
      call get_shared_variable('chit_prof2',chit_prof2,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting chit_prof2")
      call get_shared_variable('hcondzbot',hcondzbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting hcondzbot")
      call get_shared_variable('hcondztop',hcondztop,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting hcondztop")
      call get_shared_variable('lheatc_chiconst',lheatc_chiconst,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting lheatc_chiconst")
      call get_shared_variable('chi',chi,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting chi")
      call get_shared_variable('Fbot',Fbot,ierr)
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting Fbot")
      call get_shared_variable('Ftop',Ftop,caller='bc_ss_flux_condturb_z')
      if (ierr/=0) call stop_it("bc_ss_flux_condturb_z: "//&
           "there was a problem when getting Ftop")
!
      select case (topbot)
!
!  Check whether we want to do top or bottom (this is precessor dependent)
!
!  bottom boundary
!  ===============
!
      case ('bot')
!
! Do the pretend_lnTT=T case first
!
        if (pretend_lnTT) then
           call stop_it("bc_ss_flux_condturb_z: not implemented for pretend_lnTT=T")
        else
!
!  Set ghost zones such that -chi_t*rho*T*grads -hcond*gTT = Fbot
!
          call getlnrho(f(:,:,n1,ilnrho),rho_xy)      ! here rho_xy = ln(rho)
          cs2_xy=cs20*exp(gamma_m1*(rho_xy-lnrho0)+cv1*f(:,:,n1,iss))
!
          call getrho(f(:,:,n1,ilnrho),rho_xy)        ! here rho_xy = rho
!
          !fac=(1./60)*dz_1(l1)
          !dlnrhodz_xy=fac*(+ 45.0*(f(:,:,n1+1,ilnrho)-f(:,:,n1-1,ilnrho)) &
          !                 -  9.0*(f(:,:,n1+2,ilnrho)-f(:,:,n1-2,ilnrho)) &
          !                 +      (f(:,:,n1+3,ilnrho)-f(:,:,n1-3,ilnrho)))
!
          if (lheatc_chiconst) then
            dsdz_xy= (gamma_m1*Fbot/cs2_xy)/(rho_xy*(chit_prof1*chi_t/cp + gamma*chi))
            rho_xy = (chi*gamma_m1*rho_xy/(rho_xy*(chit_prof1*chi_t/cp+gamma*chi)))
          else
            dsdz_xy= (cp*gamma_m1*Fbot/cs2_xy)/(chit_prof1*chi_t*rho_xy + hcondzbot*gamma)
            rho_xy = (hcondzbot*gamma_m1/(chit_prof1*chi_t*rho_xy+gamma*hcondzbot))
          endif
!
!  Enforce ds/dz = -(cp*gamma_m1*Fbot/cs2 + K*gamma_m1*glnrho)/(gamma*K+chi_t*rho)
!
          do i=1,nghost
            call getdlnrho(f(:,:,n1-i:n1+i,ilnrho),i,cs2_xy)
            f(:,:,n1-i,iss)=f(:,:,n1+i,iss) + rho_xy*cs2_xy+dz2_bound(-i)*dsdz_xy
          enddo

        endif
!
!  top boundary
!  ============
!
      case ('top')
!
         call stop_it("bc_ss_flux_condturb_z: not implemented for the top boundary")
!
!  capture undefined entries
!
      case default
        call fatal_error('bc_ss_flux_condturb_z','invalid argument')
      endselect
!
    endsubroutine bc_ss_flux_condturb_z
!***********************************************************************
    subroutine bc_ss_temp_old(f,topbot)
!
!  boundary condition for entropy: constant temperature
!
!  23-jan-2002/wolf: coded
!  11-jun-2002/axel: moved into the entropy module
!   8-jul-2002/axel: split old bc_ss into two
!  23-jun-2003/tony: implemented for leos_fixed_ionization
!  26-aug-2003/tony: distributed across ionization modules
!
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho

      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my) :: tmp_xy
      integer :: i
      real, dimension(:,:), pointer :: reference_state
!
      if (ldebug) print*,'bc_ss_temp_old: ENTER - cs20,cs0=',cs20,cs0
!
      if (lreference_state) &
         call get_shared_variable('reference_state',reference_state,caller='bc_ss_temp_old')
!
!  Do the `c2' boundary condition (fixed temperature/sound speed) for entropy.
!  This assumes that the density is already set (ie density must register
!  first!)
!  tmp_xy = s(x,y) on the boundary.
!  gamma*s/cp = [ln(cs2/cs20)-(gamma-1)ln(rho/rho0)]
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
!
        if ((bcz1(ilnrho) /= 'a2') .and. (bcz1(ilnrho) /= 'a3')) &
          call fatal_error('bc_ss_temp_old','Inconsistent boundary conditions 3.')
        if (ldebug) print*, 'bc_ss_temp_old: set bottom temperature: cs2bot=',cs2bot
        if (cs2bot<=0.) print*,'bc_ss_temp_old: cannot have cs2bot = ', cs2bot, ' <= 0'
!
        call getlnrho(f(:,:,n1,ilnrho),tmp_xy)
        tmp_xy = (-gamma_m1*(tmp_xy-lnrho0) + log(cs2bot/cs20)) / gamma

        f(:,:,n1,iss) = tmp_xy
        if (lreference_state) f(:,:,n1,iss) = f(:,:,n1,iss) - transpose(spread(reference_state(:,iref_s),1,my))

        do i=1,nghost
          f(:,:,n1-i,iss) = 2*tmp_xy - f(:,:,n1+i,iss)     ! reference_state?
        enddo
!
!  top boundary
!
      case ('top')
!
        if ((bcz1(ilnrho) /= 'a2') .and. (bcz1(ilnrho) /= 'a3')) &
          call fatal_error('bc_ss_temp_old','Inconsistent boundary conditions 3.')
        if (ldebug) print*, 'bc_ss_temp_old: set top temperature - cs2top=',cs2top
        if (cs2top<=0.) print*, 'bc_ss_temp_old: cannot have cs2top = ',cs2top, ' <= 0'
!
  !     if (bcz1(ilnrho) /= 'a2') &
  !          call fatal_error('bc_ss_temp_old','Inconsistent boundary conditions 4.')
        call getlnrho(f(:,:,n2,ilnrho),tmp_xy)
        tmp_xy = (-gamma_m1*(tmp_xy-lnrho0) + log(cs2top/cs20)) / gamma

        f(:,:,n2,iss) = tmp_xy
        if (lreference_state) &
          f(:,:,n2,iss) = f(:,:,n2,iss) - transpose(spread(reference_state(:,iref_s),1,my))
!
        do i=1,nghost
          f(:,:,n2+i,iss) = 2*tmp_xy - f(:,:,n2-i,iss)     ! reference_state?
        enddo
!
      case default
        call fatal_error('bc_ss_temp_old','invalid argument')
      endselect
!
    endsubroutine bc_ss_temp_old
!***********************************************************************
    subroutine bc_ss_temp_x(f,topbot)
!
!  boundary condition for entropy: constant temperature
!
!   3-aug-2002/wolf: coded
!  26-aug-2003/tony: distributed across ionization modules
!
      use SharedVariables, only: get_shared_variable
      use DensityMethods, only: getlnrho 
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real :: tmp
      real, dimension(my,mz) :: lnrho_yz
      integer :: i
      real, dimension(:,:), pointer :: reference_state
!
      if (ldebug) print*,'bc_ss_temp_x: cs20,cs0=',cs20,cs0
!
!  Get the shared variables
!
      if (lreference_state) &
        call get_shared_variable('reference_state',reference_state,caller='bc_ss_temp_x')
!
!  Constant temperature/sound speed for entropy, i.e. antisymmetric
!  ln(cs2) relative to cs2top/cs2bot.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        if (ldebug) print*, 'bc_ss_temp_x: set x bottom temperature: cs2bot=',cs2bot
        if (cs2bot<=0.) print*, 'bc_ss_temp_x: cannot have cs2bot<=0'
!
        if (lentropy .and. .not. pretend_lnTT) then
          tmp = 2*cv*log(cs2bot/cs20)
          call getlnrho(f(l1,:,:,ilnrho),lnrho_yz,BOT)
          f(l1,:,:,iss) =   0.5*tmp - (cp-cv)*(lnrho_yz - lnrho0)
!
          if (lreference_state) &
            f(l1,:,:,iss) = f(l1,:,:,iss) - reference_state(BOT,iref_s)
        
          if (ldensity_nolog) then 
            do i=1,nghost
              if (lreference_state) then
!
! Reference state assumed symmetric about boundary point.
!
                f(l1-i,:,:,iss) = - f(l1+i,:,:,iss) + tmp - 2*reference_state(i,iref_s) &
                                  - (cp-cv)*(log( (f(l1+i,:,:,irho)+reference_state(i,iref_rho)) &
                                   *(f(l1-i,:,:,irho)+reference_state(i,iref_rho)) ) - 2*lnrho0)
              else
                f(l1-i,:,:,iss) = - f(l1+i,:,:,iss) + tmp &
                                  - (cp-cv)*(log(f(l1+i,:,:,irho)*f(l1-i,:,:,irho)) - 2*lnrho0)
              endif
            enddo
          else
            do i=1,nghost
              f(l1-i,:,:,iss) = - f(l1+i,:,:,iss) + tmp &
                                - (cp-cv)*(f(l1+i,:,:,ilnrho)+f(l1-i,:,:,ilnrho)-2*lnrho0)
            enddo
          endif
!
        elseif (lentropy .and. pretend_lnTT) then
           f(l1,:,:,iss) = log(cs2bot/gamma_m1)
           do i=1,nghost; f(l1-i,:,:,iss)=2*f(l1,:,:,iss)-f(l1+i,:,:,iss); enddo
        elseif (ltemperature) then
           f(l1,:,:,ilnTT) = log(cs2bot/gamma_m1)
           do i=1,nghost; f(l1-i,:,:,ilnTT)=2*f(l1,:,:,ilnTT)-f(l1+i,:,:,ilnTT); enddo
        endif
!
!  top boundary
!
      case ('top')
        if (ldebug) print*, 'bc_ss_temp_x: set x top temperature: cs2top=',cs2top
        if (cs2top<=0.) print*, 'bc_ss_temp_x: cannot have cs2top<=0'
!
        if (lentropy .and. .not. pretend_lnTT) then

          tmp = 2*cv*log(cs2top/cs20)
          call getlnrho(f(l2,:,:,ilnrho),lnrho_yz,TOP)
          f(l2,:,:,iss) = 0.5*tmp - (cp-cv)*(lnrho_yz - lnrho0)
!
          if (lreference_state) &
            f(l2,:,:,iss) = f(l2,:,:,iss) - reference_state(TOP,iref_s)
!
!  Distinguish cases for linear and logarithmic density
!
          if (ldensity_nolog) then
            do i=1,nghost
              if (lreference_state) then
!
! Reference state assumed symmetric about boundary point.
!
                f(l2+i,:,:,iss) =-f(l2-i,:,:,iss) + tmp - 2.*reference_state(nx-i,iref_s) &
                                 - (cp-cv)*(log((f(l2-i,:,:,irho)+reference_state(nx-i,iref_rho)) &
                                               *(f(l2+i,:,:,irho)+reference_state(nx-i,iref_rho)))-2*lnrho0)
              else
                f(l2+i,:,:,iss) = -f(l2-i,:,:,iss) + tmp &
                                  -(cp-cv)*(log(f(l2-i,:,:,irho)*f(l2+i,:,:,irho))-2*lnrho0)
              endif
            enddo
          else
            do i=1,nghost
              f(l2+i,:,:,iss) = -f(l2-i,:,:,iss) + tmp &
                                - (cp-cv)*(f(l2-i,:,:,ilnrho)+f(l2+i,:,:,ilnrho)-2*lnrho0)
            enddo
          endif
        elseif (lentropy .and. pretend_lnTT) then
          f(l2,:,:,iss) = log(cs2top/gamma_m1)
          do i=1,nghost; f(l2+i,:,:,iss)=2*f(l2,:,:,iss)-f(l2-i,:,:,iss); enddo
        elseif (ltemperature) then
          f(l2,:,:,ilnTT) = log(cs2top/gamma_m1)
          do i=1,nghost; f(l2+i,:,:,ilnTT)=2*f(l2,:,:,ilnTT)-f(l2-i,:,:,ilnTT); enddo
        endif
!
      case default
        call fatal_error('bc_ss_temp_x','invalid argument')
      endselect
!
    endsubroutine bc_ss_temp_x
!***********************************************************************
    subroutine bc_ss_temp_y(f,topbot)
!
!  boundary condition for entropy: constant temperature
!
!   3-aug-2002/wolf: coded
!  26-aug-2003/tony: distributed across ionization modules
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real :: tmp
      integer :: i
!
      if (ldebug) print*,'bc_ss_temp_y: cs20,cs0=',cs20,cs0
!
!  Constant temperature/sound speed for entropy, i.e. antisymmetric
!  ln(cs2) relative to cs2top/cs2bot.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is precessor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        if (ldebug) print*, &
                   'bc_ss_temp_y: set y bottom temperature - cs2bot=',cs2bot
        if (cs2bot<=0.) print*, 'bc_ss_temp_y: cannot have cs2bot<=0'
!
        tmp = 2*cv*log(cs2bot/cs20)
        f(:,m1,:,iss) = 0.5*tmp - (cp-cv)*(f(:,m1,:,ilnrho)-lnrho0)
        do i=1,nghost
          f(:,m1-i,:,iss) = -f(:,m1+i,:,iss) + tmp &
               - (cp-cv)*(f(:,m1+i,:,ilnrho)+f(:,m1-i,:,ilnrho)-2*lnrho0)
        enddo
!
!  top boundary
!
      case ('top')
        if (ldebug) print*, &
                     'bc_ss_temp_y: set y top temperature - cs2top=',cs2top
        if (cs2top<=0.) print*, 'bc_ss_temp_y: cannot have cs2top<=0'

        tmp = 2*cv*log(cs2top/cs20)
        f(:,m2,:,iss) = 0.5*tmp - (cp-cv)*(f(:,m2,:,ilnrho)-lnrho0)
        do i=1,nghost
          f(:,m2+i,:,iss) = -f(:,m2-i,:,iss) + tmp &
               - (cp-cv)*(f(:,m2-i,:,ilnrho)+f(:,m2+i,:,ilnrho)-2*lnrho0)
        enddo
!
      case default
        call fatal_error('bc_ss_temp_y','invalid argument')
      endselect
!
    endsubroutine bc_ss_temp_y
!***********************************************************************
    subroutine bc_ss_temp_z(f,topbot)
!
!  boundary condition for entropy: constant temperature
!
!   3-aug-2002/wolf: coded
!  26-aug-2003/tony: distributed across ionization modules
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real :: tmp
      integer :: i
!
      if (ldebug) print*,'bc_ss_temp_z: cs20,cs0=',cs20,cs0
!
!  Constant temperature/sound speed for entropy, i.e. antisymmetric
!  ln(cs2) relative to cs2top/cs2bot.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        if (ldebug) print*, &
                   'bc_ss_temp_z: set z bottom temperature: cs2bot=',cs2bot
        if (cs2bot<=0.) print*, &
                   'bc_ss_temp_z: cannot have cs2bot = ', cs2bot, ' <= 0'
        if (lentropy .and. .not. pretend_lnTT) then
!
!  Distinguish cases for linear and logarithmic density
!
           tmp = 2*cv*log(cs2bot/cs20)
           if (ldensity_nolog) then
             f(:,:,n1,iss) = 0.5*tmp - (cp-cv)*(alog(f(:,:,n1,irho))-lnrho0)
             do i=1,nghost
               f(:,:,n1-i,iss) = -f(:,:,n1+i,iss) + tmp &
               !   - (cp-cv)*(log(f(:,:,n1+i,irho)*f(:,:,n1-i,irho))-2*lnrho0)
!AB: this could be better
                  - 2*(cp-cv)*(log(f(:,:,n1,irho))-lnrho0)
             enddo
           else
             f(:,:,n1,iss) = 0.5*tmp - (cp-cv)*(f(:,:,n1,ilnrho)-lnrho0)
             do i=1,nghost
               f(:,:,n1-i,iss) = -f(:,:,n1+i,iss) + tmp &
                   - (cp-cv)*(f(:,:,n1+i,ilnrho)+f(:,:,n1-i,ilnrho)-2*lnrho0)
             enddo
           endif
        elseif (lentropy .and. pretend_lnTT) then
            f(:,:,n1,iss) = log(cs2bot/gamma_m1)
            do i=1,nghost; f(:,:,n1-i,iss)=2*f(:,:,n1,iss)-f(:,:,n1+i,iss); enddo
        elseif (ltemperature) then
            if (ltemperature_nolog) then
              f(:,:,n1,iTT)   = cs2bot/gamma_m1
            else
              f(:,:,n1,ilnTT) = log(cs2bot/gamma_m1)
            endif
            do i=1,nghost; f(:,:,n1-i,ilnTT)=2*f(:,:,n1,ilnTT)-f(:,:,n1+i,ilnTT); enddo
        endif
!
!  top boundary
!
      case ('top')
        if (ldebug) print*, &
                   'bc_ss_temp_z: set z top temperature: cs2top=',cs2top
        if (cs2top<=0.) print*, &
                   'bc_ss_temp_z: cannot have cs2top = ', cs2top, ' <= 0'
!DM+PC next two lines need to be looked into.
!AB: This was implemented in revision: 17029 dhruba.mitra, but it works!
        if (lread_oldsnap) &
          cs2top=cs20*exp(gamma*f(l2,m2,n2,iss)/cp+gamma_m1*(f(l2,m2,n2,ilnrho)-lnrho0))
        if (lentropy .and. .not. pretend_lnTT) then
!
!  Distinguish cases for linear and logarithmic density
!
          tmp = 2*cv*log(cs2top/cs20)
          if (ldensity_nolog) then
            f(:,:,n2,iss) = 0.5*tmp - (cp-cv)*(alog(f(:,:,n2,irho))-lnrho0)
            do i=1,nghost
              f(:,:,n2+i,iss) = -f(:,:,n2-i,iss) + tmp &
                   !- (cp-cv)*(log(f(:,:,n2-i,irho)*f(:,:,n2+i,irho))-2*lnrho0)
!AB: this could be better
                   - 2*(cp-cv)*(log(f(:,:,n2,irho))-lnrho0)
            enddo
          else
            f(:,:,n2,iss) = 0.5*tmp - (cp-cv)*(f(:,:,n2,ilnrho)-lnrho0)
            do i=1,nghost
              f(:,:,n2+i,iss) = -f(:,:,n2-i,iss) + tmp &
                   - (cp-cv)*(f(:,:,n2-i,ilnrho)+f(:,:,n2+i,ilnrho)-2*lnrho0)
            enddo
          endif
        elseif (lentropy .and. pretend_lnTT) then
            f(:,:,n2,iss) = log(cs2top/gamma_m1)
            do i=1,nghost; f(:,:,n2+i,iss)=2*f(:,:,n2,iss)-f(:,:,n2-i,iss); enddo
        elseif (ltemperature) then
            if (ltemperature_nolog) then
              f(:,:,n2,iTT)   = cs2top/gamma_m1
            else
              f(:,:,n2,ilnTT) = log(cs2top/gamma_m1)
            endif
            do i=1,nghost; f(:,:,n2+i,ilnTT)=2*f(:,:,n2,ilnTT)-f(:,:,n2-i,ilnTT); enddo
        endif
!
      case default
        call fatal_error('bc_ss_temp_z','invalid argument')
      endselect
!
    endsubroutine bc_ss_temp_z
!***********************************************************************
    subroutine bc_lnrho_temp_z(f,topbot)
!
!  boundary condition for lnrho *and* ss: constant temperature
!
!  27-sep-2002/axel: coded
!  19-aug-2005/tobi: distributed across ionization modules
!
      use Gravity, only: gravz
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real :: tmp
      integer :: i
!
      if (ldebug) print*,'bc_lnrho_temp_z: cs20,cs0=',cs20,cs0
!
!  Constant temperature/sound speed for entropy, i.e. antisymmetric
!  ln(cs2) relative to cs2top/cs2bot.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        if (ldebug) print*, &
                 'bc_lnrho_temp_z: set z bottom temperature: cs2bot=',cs2bot
        if (cs2bot<=0. .and. lroot) print*, &
                 'bc_lnrho_temp_z: cannot have cs2bot<=0'
        tmp = 2*cv*log(cs2bot/cs20)
!
!  set boundary value for entropy, then extrapolate ghost pts by antisymmetry
!
        f(:,:,n1,iss) = 0.5*tmp - (cp-cv)*(f(:,:,n1,ilnrho)-lnrho0)
        do i=1,nghost; f(:,:,n1-i,iss) = 2*f(:,:,n1,iss)-f(:,:,n1+i,iss); enddo
!
!  set density in the ghost zones so that dlnrho/dz + ds/dz = gz/cs2bot
!  for the time being, we don't worry about lnrho0 (assuming that it is 0)
!
        tmp=-gravz/cs2bot
        do i=1,nghost
          f(:,:,n1-i,ilnrho)=f(:,:,n1+i,ilnrho)+cp1*f(:,:,n1+i,iss) &
                                               -cp1*f(:,:,n1-i,iss)+dz2_bound(-i)*tmp
        enddo
!
!  top boundary
!
      case ('top')
        if (ldebug) print*, &
                    'bc_lnrho_temp_z: set z top temperature: cs2top=',cs2top
        if (cs2top<=0. .and. lroot) print*, &
                    'bc_lnrho_temp_z: cannot have cs2top<=0'
        tmp = 2*cv*log(cs2top/cs20)
!
!  set boundary value for entropy, then extrapolate ghost pts by antisymmetry
!
        f(:,:,n2,iss) = 0.5*tmp - (cp-cv)*(f(:,:,n2,ilnrho)-lnrho0)
        do i=1,nghost; f(:,:,n2+i,iss) = 2*f(:,:,n2,iss)-f(:,:,n2-i,iss); enddo
!
!  set density in the ghost zones so that dlnrho/dz + ds/dz = gz/cs2top
!  for the time being, we don't worry about lnrho0 (assuming that it is 0)
!
        tmp=gravz/cs2top
        do i=1,nghost
          f(:,:,n2+i,ilnrho)=f(:,:,n2-i,ilnrho)+cp1*f(:,:,n2-i,iss) &
                                               -cp1*f(:,:,n2+i,iss)+dz2_bound(i)*tmp
        enddo
!
      case default
        call fatal_error('bc_lnrho_temp_z','invalid argument')
      endselect
!
    endsubroutine bc_lnrho_temp_z
!***********************************************************************
    subroutine bc_lnrho_pressure_z(f,topbot)
!
!  boundary condition for lnrho: constant pressure
!
!   4-apr-2003/axel: coded
!   1-may-2003/axel: added the same for top boundary
!  19-aug-2005/tobi: distributed across ionization modules
!
      use Gravity, only: lnrho_bot,lnrho_top,ss_bot,ss_top
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      integer :: i
!
      if (ldebug) print*,'bc_lnrho_pressure_z: cs20,cs0=',cs20,cs0
!
!  Constant pressure, i.e. antisymmetric
!  This assumes that the entropy is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('top')
        if (ldebug) print*,'bc_lnrho_pressure_z: lnrho_top,ss_top=',lnrho_top,ss_top
!
!  fix entropy if inflow (uz>0); otherwise leave s unchanged
!  afterwards set s antisymmetrically about boundary value
!
        if (lentropy) then
!         do m=m1,m2
!         do l=l1,l2
!           if (f(l,m,n1,iuz)>=0) then
!             f(l,m,n1,iss)=ss_bot
!           else
!             f(l,m,n1,iss)=f(l,m,n1+1,iss)
!           endif
!         enddo
!         enddo
          f(:,:,n2,iss)=ss_top
          do i=1,nghost; f(:,:,n2+i,iss)=2*f(:,:,n2,iss)-f(:,:,n2-i,iss); enddo
!
!  set density value such that pressure is constant at the bottom
!
          f(:,:,n2,ilnrho)=lnrho_top+cp1*(ss_top-f(:,:,n2,iss))
        else
          f(:,:,n2,ilnrho)=lnrho_top
        endif
!
!  make density antisymmetric about boundary
!  another possibility might be to enforce hydrostatics
!  ie to set dlnrho/dz=-g/cs^2, assuming zero entropy gradient
!
        do i=1,nghost
          f(:,:,n2+i,ilnrho)=2*f(:,:,n2,ilnrho)-f(:,:,n2-i,ilnrho)
        enddo
!
!  top boundary
!
      case ('bot')
        if (ldebug) print*,'bc_lnrho_pressure_z: lnrho_bot,ss_bot=',lnrho_bot,ss_bot
!
!  fix entropy if inflow (uz>0); otherwise leave s unchanged
!  afterwards set s antisymmetrically about boundary value
!
        if (lentropy) then
!         do m=m1,m2
!         do l=l1,l2
!           if (f(l,m,n1,iuz)>=0) then
!             f(l,m,n1,iss)=ss_bot
!           else
!             f(l,m,n1,iss)=f(l,m,n1+1,iss)
!           endif
!         enddo
!         enddo
          f(:,:,n1,iss)=ss_bot
          do i=1,nghost; f(:,:,n1-i,iss)=2*f(:,:,n1,iss)-f(:,:,n1+i,iss); enddo
!
!  set density value such that pressure is constant at the bottom
!
          f(:,:,n1,ilnrho)=lnrho_bot+ss_bot-f(:,:,n1,iss)
        else
          f(:,:,n1,ilnrho)=lnrho_bot
        endif
!
!  make density antisymmetric about boundary
!  another possibility might be to enforce hydrostatics
!  ie to set dlnrho/dz=-g/cs^2, assuming zero entropy gradient
!
        do i=1,nghost
          f(:,:,n1-i,ilnrho)=2*f(:,:,n1,ilnrho)-f(:,:,n1+i,ilnrho)
        enddo
!
      case default
        call fatal_error('bc_lnrho_pressure_z','invalid argument')
      endselect
!
    endsubroutine bc_lnrho_pressure_z
!***********************************************************************
    subroutine bc_ss_temp2_z(f,topbot)
!
!  boundary condition for entropy: constant temperature
!
!   3-aug-2002/wolf: coded
!  26-aug-2003/tony: distributed across ionization modules
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real :: tmp
      integer :: i
!
      if (ldebug) print*,'bc_ss_temp2_z: cs20,cs0=',cs20,cs0
!
!  Constant temperature/sound speed for entropy, i.e. antisymmetric
!  ln(cs2) relative to cs2top/cs2bot.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        if (ldebug) print*, &
                   'bc_ss_temp2_z: set z bottom temperature: cs2bot=',cs2bot
        if (cs2bot<=0.) print*, 'bc_ss_temp2_z: cannot have cs2bot<=0'
!
        tmp = cv*log(cs2bot/cs20)
        do i=0,nghost
          f(:,:,n1-i,iss) = tmp - (cp-cv)*(f(:,:,n1-i,ilnrho)-lnrho0)
        enddo
!
!  top boundary
!
      case ('top')
        if (ldebug) print*, &
                     'bc_ss_temp2_z: set z top temperature: cs2top=',cs2top
        if (cs2top<=0.) print*,'bc_ss_temp2_z: cannot have cs2top<=0'
!
        tmp = cv*log(cs2top/cs20)
        do i=0,nghost
          f(:,:,n2+i,iss) = tmp - (cp-cv)*(f(:,:,n2+i,ilnrho)-lnrho0)
        enddo
      case default
        call fatal_error('bc_ss_temp2_z','invalid argument')
      endselect
!
    endsubroutine bc_ss_temp2_z
!***********************************************************************
    subroutine bc_ss_temp3_z(f,topbot)
!
!  boundary condition for entropy: constant temperature
!
!  22-jan-2013/axel: coded to impose cs2bot and dcs2bot at bottom
!
      use Gravity, only: gravz
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real :: tmp,dcs2bot
      integer :: i
!
      if (ldebug) print*,'bc_ss_temp3_z: cs20,cs0=',cs20,cs0
!
!  Constant temperature/sound speed for entropy, i.e. antisymmetric
!  ln(cs2) relative to cs2top/cs2bot.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
!  Not yet adapted to reference_state
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        dcs2bot=gamma*gravz/(mpoly+1.)
        if (ldebug) print*, 'bc_ss_temp3_z: set cs2bot,dcs2bot=',cs2bot,dcs2bot
        if (cs2bot<=0.) print*, 'bc_ss_temp3_z: cannot have cs2bot<=0'

        do i=0,nghost
          f(:,:,n1-i,iss) =  cv*log((cs2bot-0.5*dz2_bound(-i)*dcs2bot)/cs20) &
                           -(cp-cv)*(f(:,:,n1-i,ilnrho)-lnrho0)
        enddo
!
!  top boundary
!
      case ('top')
        if (ldebug) print*, 'bc_ss_temp3_z: set z top temperature: cs2top=',cs2top
        if (cs2top<=0.) print*,'bc_ss_temp3_z: cannot have cs2top<=0'

        tmp = cv*log(cs2top/cs20)
        do i=0,nghost
          f(:,:,n2+i,iss) = tmp - (cp-cv)*(f(:,:,n2+i,ilnrho)-lnrho0)
        enddo
!
      case default
        call fatal_error('bc_ss_temp3_z','invalid argument')
      endselect
!
    endsubroutine bc_ss_temp3_z
!***********************************************************************
    subroutine bc_ss_stemp_x(f,topbot)
!
!  boundary condition for entropy: symmetric temperature
!
!   3-aug-2002/wolf: coded
!  26-aug-2003/tony: distributed across ionization modules
!
      use SharedVariables, only: get_shared_variable
!
      character (len=3) :: topbot
      real, dimension(mx,my,mz,mfarray) :: f
      integer :: i
      real, dimension(:,:), allocatable :: tmp
      real, dimension(:,:), pointer :: reference_state
!
      if (ldebug) print*,'bc_ss_stemp_x: cs20,cs0=',cs20,cs0
!
!  Symmetric temperature/sound speed for entropy.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
      if (lreference_state) then
        call get_shared_variable('reference_state',reference_state,caller='bc_ss_stemp_x')
        allocate(tmp(my,mz))
      endif
!
!  check whether we want to do top or bottom (this is precessor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        if (cs2bot<=0.) print*, 'bc_ss_stemp_x: cannot have cs2bot<=0'

        if (lreference_state) tmp=f(l1,:,:,irho)+reference_state(BOT,iref_rho)

        do i=1,nghost
          if (ldensity_nolog) then
            if (lreference_state) then
              f(l1-i,:,:,iss) = f(l1+i,:,:,iss) + dx2_bound(-i)*reference_state(BOT,iref_gs) &
                   + (cp-cv)*( f(l1+i,:,:,irho)-f(l1-i,:,:,irho)+dx2_bound(-i)*reference_state(BOT,iref_grho) )/tmp
            else
              f(l1-i,:,:,iss) =  f(l1+i,:,:,iss) &
                               + (cp-cv)*(log(f(l1+i,:,:,irho)/f(l1-i,:,:,irho)))
            endif
          else
            f(l1-i,:,:,iss) =  f(l1+i,:,:,iss) &
                             + (cp-cv)*(f(l1+i,:,:,ilnrho)-f(l1-i,:,:,ilnrho))
          endif
        enddo
!
!  top boundary
!
      case ('top')
        if (cs2top<=0.) print*, 'bc_ss_stemp_x: cannot have cs2top<=0'

        if (lreference_state) tmp=f(l2,:,:,irho)+reference_state(TOP,iref_rho)

        do i=1,nghost
          if (ldensity_nolog) then
            if (lreference_state) then
              f(l2+i,:,:,iss) = f(l2-i,:,:,iss) - dx2_bound(i)*reference_state(TOP,iref_gs) &
                 + (cp-cv)*(f(l2-i,:,:,ilnrho)-f(l2+i,:,:,ilnrho) - dx2_bound(i)*reference_state(TOP,iref_grho) )/tmp
            else
              f(l2+i,:,:,iss) =   f(l2-i,:,:,iss) &
                               + (cp-cv)*log(f(l2-i,:,:,ilnrho)/f(l2+i,:,:,ilnrho))
            endif
          else
            f(l2+i,:,:,iss) =   f(l2-i,:,:,iss) &
                             + (cp-cv)*(f(l2-i,:,:,ilnrho)-f(l2+i,:,:,ilnrho))
          endif
        enddo
!
      case default
        call fatal_error('bc_ss_stemp_x','invalid argument')
      endselect
!
    endsubroutine bc_ss_stemp_x
!***********************************************************************
    subroutine bc_ss_stemp_y(f,topbot)
!
!  boundary condition for entropy: symmetric temperature
!
!   3-aug-2002/wolf: coded
!  26-aug-2003/tony: distributed across ionization modules
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      integer :: i
!
      if (ldebug) print*,'bc_ss_stemp_y: cs20,cs0=',cs20,cs0
!
!  Symmetric temperature/sound speed for entropy.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is precessor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
        if (cs2bot<=0.) print*, &
                       'bc_ss_stemp_y: cannot have cs2bot<=0'
        do i=1,nghost
          f(:,m1-i,:,iss) = f(:,m1+i,:,iss) &
               + (cp-cv)*(f(:,m1+i,:,ilnrho)-f(:,m1-i,:,ilnrho))
        enddo
!
!  top boundary
!
      case ('top')
        if (cs2top<=0.) print*, &
                       'bc_ss_stemp_y: cannot have cs2top<=0'
        do i=1,nghost
          f(:,m2+i,:,iss) = f(:,m2-i,:,iss) &
               + (cp-cv)*(f(:,m2-i,:,ilnrho)-f(:,m2+i,:,ilnrho))
        enddo
!
      case default
        call fatal_error('bc_ss_stemp_y','invalid argument')
      endselect
!
    endsubroutine bc_ss_stemp_y
!***********************************************************************
    subroutine bc_ss_stemp_z(f,topbot)
!
!  boundary condition for entropy: symmetric temperature
!
!   3-aug-2002/wolf: coded
!  26-aug-2003/tony: distributed across ionization modules
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      integer :: i
!
      if (ldebug) print*,'bc_ss_stemp_z: cs20,cs0=',cs20,cs0
!
!  Symmetric temperature/sound speed for entropy.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
      case ('bot')
          if (cs2bot<=0.) print*, &
                                  'bc_ss_stemp_z: cannot have cs2bot<=0'
          do i=1,nghost
             f(:,:,n1-i,iss) = f(:,:,n1+i,iss) &
                  + (cp-cv)*(f(:,:,n1+i,ilnrho)-f(:,:,n1-i,ilnrho))
          enddo
!
!  top boundary
!
      case ('top')
        if (cs2top<=0.) print*, &
                 'bc_ss_stemp_z: cannot have cs2top<=0'
         do i=1,nghost
           f(:,:,n2+i,iss) = f(:,:,n2-i,iss) &
                + (cp-cv)*(f(:,:,n2-i,ilnrho)-f(:,:,n2+i,ilnrho))
         enddo
      case default
        call fatal_error('bc_ss_stemp_z','invalid argument')
      endselect
!
    endsubroutine bc_ss_stemp_z
!***********************************************************************
    subroutine bc_ss_a2stemp_x(f,topbot)
!
!  Boundary condition for entropy: adopt boundary value for temperature in
!  the ghost zone to handle shock profiles in interstellar with steep +ve
!  1st derivative in cooled remnant shells, followed by steep -ve 1st
!  derivative inside remnant.
!  s or a2 for temperature both unstable and unphysical as the unshocked
!  exterior ISM will be comparatively homogeneous, hence allowing the ghost
!  zone to fluctuate matching the boundary values is a reasonable approx
!  of the physical flow, whilst avoiding unphysical spikes to wreck the
!  calculation.
!
!  25-2010/fred: adapted from bc_ss_stemp_z
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      integer :: i
!
      if (ldebug) print*,'bc_ss_a2stemp_z: cs20,cs0=',cs20,cs0
!
!  Uniform temperature/sound speed condition for entropy.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is precessor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
        case ('bot')
          if (cs2bot<=0.) print*, &
              'bc_ss_a2stemp_x: cannot have cs2bot<=0'
          do i=1,nghost
            f(l1-i,:,:,iss) = f(l1+1-i,:,:,iss)+(cp-cv)* &
                (f(l1+1-i,:,:,ilnrho)-f(l1-i,:,:,ilnrho))
          enddo
!
!  top boundary
!
        case ('top')
          if (cs2top<=0.) print*, &
              'bc_ss_a2stemp_x: cannot have cs2top<=0'
          do i=1,nghost
            f(l2+i,:,:,iss) = f(l2-1+i,:,:,iss)+(cp-cv)* &
                (f(l2-1+i,:,:,ilnrho)-f(l2+i,:,:,ilnrho))
          enddo
!
        case default
          call fatal_error('bc_ss_a2stemp_x','invalid argument')
      endselect
!
    endsubroutine bc_ss_a2stemp_x
!***********************************************************************
    subroutine bc_ss_a2stemp_y(f,topbot)
!
!  Boundary condition for entropy: adopt boundary value for temperature in
!  the ghost zone to handle shock profiles in interstellar with steep +ve
!  1st derivative in cooled remnant shells, followed by steep -ve 1st
!  derivative inside remnant.
!  s or a2 for temperature both unstable and unphysical as the unshocked
!  exterior ISM will be comparatively homogeneous, hence allowing the ghost
!  zone to fluctuate matching the boundary values is a reasonable approx
!  of the physical flow, whilst avoiding unphysical spikes to wreck the
!  calculation.
!
!  25-2010/fred: adapted from bc_ss_stemp_z
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      integer :: i
!
      if (ldebug) print*,'bc_ss_a2stemp_z: cs20,cs0=',cs20,cs0
!
!  Uniform temperature/sound speed condition for entropy.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is precessor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
        case ('bot')
          if (cs2bot<=0.) print*, &
              'bc_ss_a2stemp_y: cannot have cs2bot<=0'
          do i=1,nghost
            f(:,m1-i,:,iss) = f(:,m1+1-i,:,iss)+(cp-cv)* &
                (f(:,m1+1-i,:,ilnrho)-f(:,m1-i,:,ilnrho))
          enddo
!
!  top boundary
!
        case ('top')
          if (cs2top<=0.) print*, &
              'bc_ss_a2stemp_y: cannot have cs2top<=0'
          do i=1,nghost
            f(:,m2+i,:,iss) = f(:,m2-1+i,:,iss)+(cp-cv)* &
                (f(:,m2-1+i,:,ilnrho)-f(:,m2+i,:,ilnrho))
          enddo
!
        case default
          call fatal_error('bc_ss_a2stemp_y','invalid argument')
      endselect
!
    endsubroutine bc_ss_a2stemp_y
!***********************************************************************
    subroutine bc_ss_a2stemp_z(f,topbot)
!
!  Boundary condition for entropy: adopt boundary value for temperature in
!  the ghost zone to handle shock profiles in interstellar with steep +ve
!  1st derivative in cooled remnant shells, followed by steep -ve 1st
!  derivative inside remnant.
!  s or a2 for temperature both unstable and unphysical as the unshocked
!  exterior ISM will be comparatively homogeneous, hence allowing the ghost
!  zone to fluctuate matching the boundary values is a reasonable approx
!  of the physical flow, whilst avoiding unphysical spikes to wreck the
!  calculation.
!
!  25-2010/fred: adapted from bc_ss_stemp_z
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      integer :: i
!
      if (ldebug) print*,'bc_ss_a2stemp_z: cs20,cs0=',cs20,cs0
!
!  Uniform temperature/sound speed condition for entropy.
!  This assumes that the density is already set (ie density _must_ register
!  first!)
!
!  check whether we want to do top or bottom (this is processor dependent)
!
      select case (topbot)
!
!  bottom boundary
!
        case ('bot')
          if (cs2bot<=0.) print*, &
              'bc_ss_a2stemp_z: cannot have cs2bot<=0'
          do i=1,nghost
            f(:,:,n1-i,iss) = f(:,:,n1+1-i,iss) + (cp-cv)* &
                (f(:,:,n1+1-i,ilnrho)-f(:,:,n1-i,ilnrho))
          enddo
!
!  top boundary
!
        case ('top')
          if (cs2top<=0.) print*, &
              'bc_ss_a2stemp_z: cannot have cs2top<=0'
          do i=1,nghost
            f(:,:,n2+i,iss) = f(:,:,n2-1+i,iss) + (cp-cv)* &
                (f(:,:,n2-1+i,ilnrho)-f(:,:,n2+i,ilnrho))
          enddo
        case default
          call fatal_error('bc_ss_a2stemp_z','invalid argument')
      endselect
!
    endsubroutine bc_ss_a2stemp_z
!***********************************************************************
    subroutine bc_ss_energy(f,topbot)
!
!  boundary condition for entropy
!
!  may-2002/nils: coded
!  11-jul-2002/nils: moved into the entropy module
!  26-aug-2003/tony: distributed across ionization modules
!
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my) :: cs2_2d
      integer :: i
!
!  The 'ce' boundary condition for entropy makes the energy constant at
!  the boundaries.
!  This assumes that the density is already set (ie density must register
!  first!)
!
    select case (topbot)
!
! Bottom boundary
!
    case ('bot')
      !  Set cs2 (temperature) in the ghost points to the value on
      !  the boundary
      !
      cs2_2d=cs20*exp(gamma_m1*f(:,:,n1,ilnrho)+cv1*f(:,:,n1,iss))
      do i=1,nghost
         f(:,:,n1-i,iss)=cv*(-gamma_m1*f(:,:,n1-i,ilnrho)-log(cs20)&
              +log(cs2_2d))
      enddo
!
! Top boundary
!
    case ('top')
      !  Set cs2 (temperature) in the ghost points to the value on
      !  the boundary
      !
      cs2_2d=cs20*exp(gamma_m1*f(:,:,n2,ilnrho)+cv1*f(:,:,n2,iss))
      do i=1,nghost
         f(:,:,n2+i,iss)=cv*(-gamma_m1*f(:,:,n2+i,ilnrho)-log(cs20)&
              +log(cs2_2d))
      enddo
    case default
      call fatal_error('bc_ss_energy','invalid argument')
    endselect
!
    endsubroutine bc_ss_energy
!***********************************************************************
    subroutine bc_stellar_surface(f,topbot)
!
      use Mpicomm, only: stop_it
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mfarray) :: f
!
      call stop_it("bc_stellar_surface: NOT IMPLEMENTED IN EOS_IDEALGAS")
      call keep_compiler_quiet(f)
      call keep_compiler_quiet(topbot)
!
    endsubroutine bc_stellar_surface
!***********************************************************************
    subroutine bc_lnrho_cfb_r_iso(f,topbot)
!
!  Boundary condition for radial centrifugal balance
!
!  This sets
!    \partial_{r} \ln\rho
!  such that
!    (\partial_{r} p)/\rho = cs^2 \partial_{r} \ln\rho} = uphi**2/rad - \partial_{r} Phi
!  where Phi is the gravitational potential
!
!  i.e. it enforces centrifugal balance at the boundary.
!
!  As it is, works only for isobaric, isothermal and cylindrical coordinates
!
!  21-aug-2006/wlad: coded
!
      use Gravity, only: potential
      use Sub, only: div
!
      real, dimension (mx,my,mz,mfarray), intent (inout) :: f
      character (len=3), intent (in) :: topbot
      real, dimension (my,mz) :: cs2,gravterm,centterm,uphi
      real :: potp,potm,rad,step
      integer :: i
!
      select case (topbot)
!
!  Bottom boundary
!
      case ('bot')
        do i=1,nghost
!
          cs2 = cs20
          call potential(R=x(l1-i),pot=potm)
          call potential(R=x(l1+i),pot=potp)
!
          gravterm= -(potm-potp)/cs2
!
          step=-dx2_bound(-i)
          rad=x(l1-i)
          uphi=f(l1-i,:,:,iuy)
!
          centterm= uphi**2 * step/(rad*cs2)  !???
          if (ldensity_nolog) then
            f(l1-i,:,:,ilnrho)=f(l1+i,:,:,irho)*exp(gravterm + centterm)
          else
            f(l1-i,:,:,ilnrho)=f(l1+i,:,:,ilnrho) + gravterm + centterm
          endif
!
          !print*,'potentials',potm,potp,-(potm-potp)
          !print*,'centrifugal',f(l1-i,mpoint,npoint,iuy)**2 *step/rad
          !stop
!
        enddo
!
!  Top boundary
!
      case ('top')
        do i=1,nghost
!
          cs2 = cs20
          call potential(R=x(l2+i),pot=potp)
          call potential(R=x(l2-i),pot=potm)
!
          gravterm= -(potp-potm)/cs2
!
          step=dx2_bound(i)
          rad=x(l2+i)
          uphi=f(l2+i,:,:,iuy)
!
          centterm= uphi**2 * step/(rad*cs2)
          if (ldensity_nolog) then
            f(l2+i,:,:,irho)   = f(l2-i,:,:,irho)*exp(gravterm + centterm)
          else
            f(l2+i,:,:,ilnrho) = f(l2-i,:,:,ilnrho) + gravterm + centterm
          endif
!
          !if (i==nghost) then
          !  print*,'potentials',potp,potm,-potp+potm,-(potp-potm)
          !  print*,'centrifugal',f(l2+i,mpoint,npoint,iuy)**2 *step/rad
          !  stop
          !endif
        enddo
!
      case default
!
      endselect
!
    endsubroutine bc_lnrho_cfb_r_iso
!***********************************************************************
    subroutine bc_lnrho_hds_z_iso(f,topbot)
!
!  Boundary condition for density *and* entropy.
!
!  This sets
!    \partial_{z} \ln\rho
!  such that
!    \partial_{z} p = \rho g_{z},
!  i.e. it enforces hydrostatic equlibrium at the boundary.
!
!  Currently this is only correct if
!    \partial_{z} lnT = 0
!  at the boundary.
!
!  12-Juil-2006/dintrans: coded
!
      use Gravity, only: potential, gravz
      use Sub, only: div
!
      real, dimension (mx,my,mz,mfarray), intent (inout) :: f
      character (len=3), intent (in) :: topbot
!
      real, dimension (mx,my) :: cs2
      real, dimension (nx) :: shock,divu
      real :: dlnrhodz, dssdz, cs2_point
      real :: potp,potm
      integer :: i
!
      select case (topbot)
!
!  Bottom boundary
!
      case ('bot')
!
        if (lentropy) then
!
!  The following might work for anelastic
!
          if (ldensity) then
            if (bcz1(iss)/='hs') then
              call fatal_error("bc_lnrho_hydrostatic_z", &
                "This boundary condition for density is "// &
                "currently only correct for bcz1(iss)='hs'")
            endif
!
            call eoscalc(ilnrho_ss,f(l1,m1,n1,ilnrho),f(l1,m1,n1,iss), &
                         cs2=cs2_point)
!
            dlnrhodz =  gamma *gravz/cs2_point
            dssdz    = -gamma_m1*gravz/cs2_point
!
            do i=1,nghost
              f(:,:,n1-i,ilnrho) = f(:,:,n1+i,ilnrho) - dz2_bound(-i)*dlnrhodz
              f(:,:,n1-i,iss   ) = f(:,:,n1+i,iss   ) - dz2_bound(-i)*dssdz
            enddo
          else if (lanelastic) then
            if (bcz1(iss_b)/='hs') then
              call fatal_error("bc_lnrho_hydrostatic_z", &
                "This boundary condition for density is "// &
                "currently only correct for bcz1(iss)='hs'")
            endif
            call eoscalc(ipp_ss,log(f(l1,m1,n1,irho_b)),f(l1,m1,n1,iss_b), &
                         cs2=cs2_point)
!
            dlnrhodz =  gamma *gravz/cs2_point
            dssdz    = gamma_m1*gravz/cs2_point
!
            do i=1,nghost
              f(:,:,n1-i,irho_b) = f(:,:,n1+i,irho_b) - dz2_bound(-i)*dlnrhodz*f(:,:,n1+1,irho_b)
              f(:,:,n1-i,iss_b ) = f(:,:,n1+i,iss_b ) - dz2_bound(-i)*dssdz
            enddo
          endif
!
        elseif (ltemperature) then
!
!  Energy equation formulated in logarithmic temperature.
!
          if (bcz1(ilntt)/='s') then
            call fatal_error("bc_lnrho_hydrostatic_z", &
                "This boundary condition for density is "// &
                "currently only correct for bcz1(ilntt)='s'")
          endif
!
          call eoscalc(ilnrho_lntt,f(l1,m1,n1,ilnrho),f(l1,m1,n1,ilntt), &
                       cs2=cs2_point)
!
          dlnrhodz =  gamma *gravz/cs2_point
!
          do i=1,nghost
            f(:,:,n1-i,ilnrho) = f(:,:,n1+i,ilnrho) - dz2_bound(-i)*dlnrhodz
          enddo
!
        else
!
!  Isothermal or polytropic equations of state.
!
          do i=1,nghost
            call potential(z=z(n1-i),pot=potm)
            call potential(z=z(n1+i),pot=potp)
            cs2 = cs2bot
!
            if (.false.) then
              ! Note: Since boundconds_x and boundconds_y are called first,
              ! this doesn't set the corners properly. However, this is
              ! not a problem since cross derivatives of density are never
              ! needed.
              n = n1+i
              do m = m1,m2
                shock = f(l1:l2,m,n,ishock)
                call div(f,iuu,divu)
                cs2(l1:l2,m) = cs2bot - shock*divu
              enddo
            endif
!
            if (ldensity_nolog) then
              f(:,:,n1-i,irho)   = f(:,:,n1+i,irho)*exp(-(potm-potp)/cs2)
            else
              f(:,:,n1-i,ilnrho) = f(:,:,n1+i,ilnrho) - (potm-potp)/cs2
            endif
!
          enddo
!
        endif
!
!  Top boundary
!
      case ('top')
!
        if (lentropy) then
!
          if (bcz2(iss)/='hs') then
            call fatal_error("bc_lnrho_hydrostatic_z", &
                "This boundary condition for density is "//&
                "currently only correct for bcz2(iss)='hs'")
          endif
!
          call eoscalc(ilnrho_ss,f(l2,m2,n2,ilnrho),f(l2,m2,n2,iss), &
                       cs2=cs2_point)
!
          dlnrhodz =  gamma *gravz/cs2_point
          dssdz    = -gamma_m1*gravz/cs2_point
!
          do i=1,nghost
            f(:,:,n2+i,ilnrho) = f(:,:,n2-i,ilnrho) + dz2_bound(i)*dlnrhodz
            f(:,:,n2+i,iss   ) = f(:,:,n2-i,iss   ) + dz2_bound(i)*dssdz
          enddo
!
        elseif (ltemperature) then
!
!  Energy equation formulated in logarithmic temperature.
!
          if (bcz2(ilntt)/='s') then
            call fatal_error("bc_lnrho_hydrostatic_z", &
                "This boundary condition for density is "//&
                "currently only correct for bcz2(ilntt)='s'")
          endif
!
          call eoscalc(ilnrho_lntt,f(l2,m2,n2,ilnrho),f(l2,m2,n2,ilntt), &
                       cs2=cs2_point)
!
          dlnrhodz =  gamma *gravz/cs2_point
!
          do i=1,nghost
            f(:,:,n2+i,ilnrho) = f(:,:,n2-i,ilnrho) + dz2_bound(i)*dlnrhodz
          enddo
!
        else
!
!  Isothermal or polytropic equations of state.
!
          do i=1,nghost
            call potential(z=z(n2+i),pot=potp)
            call potential(z=z(n2-i),pot=potm)
            cs2 = cs2bot
            if (.false.) then
              ! Note: Since boundconds_x and boundconds_y are called first,
              ! this doesn't set the corners properly. However, this is
              ! not a problem since cross derivatives of density are never
              ! needed.
              n = n2-i
              do m = m1,m2
                shock = f(l1:l2,m,n,ishock)
                call div(f,iuu,divu)
                cs2(l1:l2,m) = cs2top - shock*divu
              enddo
            else
            endif
            if (ldensity_nolog) then
              f(:,:,n2+i,irho)   = f(:,:,n2-i,irho)*exp(-(potp-potm)/cs2)
            else
              f(:,:,n2+i,ilnrho) = f(:,:,n2-i,ilnrho) - (potp-potm)/cs2
            endif
          enddo
!
        endif
!
      case default
!
      endselect
!
    endsubroutine bc_lnrho_hds_z_iso
!***********************************************************************
    subroutine bc_lnrho_hdss_z_iso(f,topbot)
!
!  Smooth out density perturbations with respect to hydrostatic
!  stratification in Fourier space.
!
!  Note: Since boundconds_x and boundconds_y are called first,
!  this doesn't set the corners properly. However, this is
!  not a problem since cross derivatives of density are never
!  needed.
!
!  05-jul-07/tobi: Adapted from bc_aa_pot3
!
      use Fourier, only: fourier_transform_xy_xy, fourier_transform_other
      use Gravity, only: potential
!
      real, dimension (mx,my,mz,mfarray), intent (inout) :: f
      character (len=3), intent (in) :: topbot
!
      real, dimension (nx,ny) :: kx,ky,kappa,exp_fact
      real, dimension (nx,ny) :: tmp_re,tmp_im
      real :: pot
      integer :: i
!
!  Get local wave numbers
!
      kx = spread(kx_fft(ipx*nx+1:ipx*nx+nx),2,ny)
      ky = spread(ky_fft(ipy*ny+1:ipy*ny+ny),1,nx)
!
!  Calculate 1/k^2, zero mean
!
      if (lshear) then
        kappa = sqrt((kx+ky*deltay/Lx)**2+ky**2)
      else
        kappa = sqrt(kx**2 + ky**2)
      endif
!
!  Check whether we want to do top or bottom (this is precessor dependent)
!
      select case (topbot)
!
!  Potential field condition at the bottom
!
      case ('bot')
!
        do i=1,nghost
!
! Calculate delta_z based on z(), not on dz to improve behavior for
! non-equidistant grid (still not really correct, but could be OK)
!
          exp_fact = exp(-kappa*(z(n1+i)-z(n1-i)))
!
!  Determine potential field in ghost zones
!
          !  Fourier transforms of x- and y-components on the boundary
          call potential(z=z(n1+i),pot=pot)
          if (ldensity_nolog) then
            tmp_re = f(l1:l2,m1:m2,n1+i,irho)*exp(+pot/cs2bot)
          else
            tmp_re = f(l1:l2,m1:m2,n1+i,ilnrho) + pot/cs2bot
          endif
          tmp_im = 0.0
          if (nxgrid>1 .and. nygrid>1) then
            call fourier_transform_xy_xy(tmp_re,tmp_im)
          else
            call fourier_transform_other(tmp_re,tmp_im)
          endif
          tmp_re = tmp_re*exp_fact
          tmp_im = tmp_im*exp_fact
          ! Transform back
          if (nxgrid>1 .and. nygrid>1) then
            call fourier_transform_xy_xy(tmp_re,tmp_im,linv=.true.)
          else
            call fourier_transform_other(tmp_re,tmp_im,linv=.true.)
          endif
          call potential(z=z(n1-i),pot=pot)
          if (ldensity_nolog) then
            f(l1:l2,m1:m2,n1-i,irho)   = tmp_re*exp(-pot/cs2bot)
          else
            f(l1:l2,m1:m2,n1-i,ilnrho) = tmp_re - pot/cs2bot
          endif
!
        enddo
!
!  Potential field condition at the top
!
      case ('top')
!
        do i=1,nghost
!
! Calculate delta_z based on z(), not on dz to improve behavior for
! non-equidistant grid (still not really correct, but could be OK)
!
          exp_fact = exp(-kappa*(z(n2+i)-z(n2-i)))
!
!  Determine potential field in ghost zones
!
          !  Fourier transforms of x- and y-components on the boundary
          call potential(z=z(n2-i),pot=pot)
          if (ldensity_nolog) then
            tmp_re = f(l1:l2,m1:m2,n2-i,irho)*exp(+pot/cs2top)
          else
            tmp_re = f(l1:l2,m1:m2,n2-i,ilnrho) + pot/cs2top
          endif
          tmp_im = 0.0
          if (nxgrid>1 .and. nygrid>1) then
            call fourier_transform_xy_xy(tmp_re,tmp_im)
          else
            call fourier_transform_other(tmp_re,tmp_im)
          endif
          tmp_re = tmp_re*exp_fact
          tmp_im = tmp_im*exp_fact
          ! Transform back
          if (nxgrid>1 .and. nygrid>1) then
            call fourier_transform_xy_xy(tmp_re,tmp_im,linv=.true.)
          else
            call fourier_transform_other(tmp_re,tmp_im,linv=.true.)
          endif
          call potential(z=z(n2+i),pot=pot)
          if (ldensity_nolog) then
            f(l1:l2,m1:m2,n2+i,irho)   = tmp_re*exp(-pot/cs2top)
          else
            f(l1:l2,m1:m2,n2+i,ilnrho) = tmp_re - pot/cs2top
          endif
!
        enddo
!
      case default
!
        if (lroot) print*,"bc_lnrho_hydrostatic_z_smooth: invalid argument"
!
      endselect
!
    endsubroutine bc_lnrho_hdss_z_iso
!***********************************************************************
    subroutine read_transport_data
!
      real, dimension (mx,my,mz,mfarray) :: f
!
      call keep_compiler_quiet(f)
!
    endsubroutine read_transport_data
!***********************************************************************
    subroutine write_thermodyn()
!
      real, dimension (mx,my,mz,mfarray) :: f
!
      call keep_compiler_quiet(f)
!
    endsubroutine write_thermodyn
!***********************************************************************
    subroutine read_thermodyn(input_file)
!
      character (len=*), intent(in) :: input_file
!
      call keep_compiler_quiet(input_file)
!
    endsubroutine read_thermodyn
!***********************************************************************
    subroutine read_species(input_file)
!
      character (len=*) :: input_file
!
      call keep_compiler_quiet(input_file)
!
    endsubroutine read_species
!***********************************************************************
    subroutine find_species_index(species_name,ind_glob,ind_chem,found_specie)
!
      integer, intent(out) :: ind_glob
      integer, intent(inout) :: ind_chem
      character (len=*), intent(in) :: species_name
      logical, intent(out) :: found_specie
!
       call keep_compiler_quiet(ind_glob)
       call keep_compiler_quiet(ind_chem)
       call keep_compiler_quiet(species_name)
       call keep_compiler_quiet(found_specie)
!
     endsubroutine find_species_index
!***********************************************************************
     subroutine find_mass(element_name,MolMass)
!
       character (len=*), intent(in) :: element_name
       real, intent(out) :: MolMass
!
       call keep_compiler_quiet(element_name)
       call keep_compiler_quiet(MolMass)
!
     endsubroutine find_mass
!***********************************************************************
    subroutine read_Lewis
!
!  Dummy routine
!
    endsubroutine read_Lewis
!***********************************************************************
    subroutine get_stratz(z, rho0z, dlnrho0dz, eth0z)
!
!  Get background stratification in z direction.
!
!  13-oct-14/ccyang: coded.
!
      real, dimension(:), intent(in) :: z
      real, dimension(:), intent(out), optional :: rho0z, dlnrho0dz, eth0z
!
      real, dimension(size(z)) :: rho, dlnrhodz
      logical :: info
      real :: h
!
      info = lroot .and. .not. lstratset
!
      gz: select case (gztype)
!
!  No stratification
!
      case ('zero', 'none') gz
        rho = rho0
        dlnrhodz = 0.0
!
!  Linear acceleration: -gz_coeff^2 * z
!
      case ('linear') gz
        if (gz_coeff == 0.0) call fatal_error('set_stratz', 'gz_coeff = 0')
        if (info) print *, 'Set z stratification: g_z = -gz_coeff^2 * z'
        h = cs0 / gz_coeff
        rho = rho0 * exp(-0.5 * (z / h)**2)
        dlnrhodz = -z / h**2
!
      case default gz
        call fatal_error('set_stratz', 'unknown type of stratification; gztype = ' // trim(gztype))
!
      endselect gz
!
      if (present(rho0z)) rho0z = rho
      if (present(dlnrho0dz)) dlnrho0dz = dlnrhodz
!
!  Energy stratification
!
      if (lthermal_energy .and. present(eth0z)) eth0z = cs20 / (gamma * gamma_m1) * rho
!
    endsubroutine get_stratz
!***********************************************************************
    subroutine set_stratz()
!
!  Set background stratification in z direction.
!
!  13-oct-14/ccyang: coded.
!
      call get_stratz(z, rho0z, dlnrho0dz, eth0z)
!
    endsubroutine set_stratz
!***********************************************************************
endmodule EquationOfState
