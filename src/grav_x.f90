! $Id: grav_x.f90,v 1.10 2005-06-26 17:34:13 eos_merger_tony Exp $

!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! MVAR CONTRIBUTION 0
! MAUX CONTRIBUTION 0
!
!***************************************************************

module Gravity

!  Gravity in the x-direction

  use Cdata
  use Cparam

  implicit none

  interface potential
    module procedure potential_global
    module procedure potential_penc
    module procedure potential_point
  endinterface
!
!  parameters used throughout entire module
!  xinfty is currently prescribed (=0)
!
  real, dimension(nx) :: gravx_pencil=0.,gravy_pencil=0.,gravz_pencil=0.
  real, dimension(nx) :: potx_pencil=0.
  real :: gravx=0.,xinfty=0.,xgrav=0.,dgravx=0., pot_ratio=1.

! parameters needed for compatibility
!
  real :: z1=0.,z2=1.,zref=0.,gravz=0.,zinfty,zgrav=impossible,nu_epicycle=1.
  real :: lnrho_bot,lnrho_top,ss_bot,ss_top
  real :: grav_const=1.
  real :: g0=0.,r0_pot=0.,kx_gg=1.,ky_gg=1.,kz_gg=1.
  integer :: n_pot=10
  character (len=labellen) :: grav_profile='const'
  logical :: lnumerical_equilibrium=.false.

  namelist /grav_init_pars/ &
       grav_profile,gravx,xgrav,dgravx,pot_ratio,kx_gg,ky_gg,kz_gg

!  It would be rather unusual to change the profile during the
!  run, but "adjusting" the profile slighly may be quite useful.

  namelist /grav_run_pars/ &
       grav_profile,gravx,xgrav,dgravx,pot_ratio,kx_gg,ky_gg,kz_gg, &
       lgravx_gas, lgravx_dust

  ! other variables (needs to be consistent with reset list below)
  integer :: idiag_curlggrms=0,idiag_curlggmax=0,idiag_divggrms=0
  integer :: idiag_divggmax=0

  contains

!***********************************************************************
    subroutine register_gravity()
!
!  initialise gravity flags
!
!  12-jun-04/axel: adapted from grav_z
!
      use Cdata
      use Mpicomm
      use Sub
!
      logical, save :: first=.true.
!
      if (.not. first) call stop_it('register_gravity: called twice')
      first = .false.
!
!  identify version number (generated automatically by CVS)
!
      if (lroot) call cvs_id( &
           "$Id: grav_x.f90,v 1.10 2005-06-26 17:34:13 eos_merger_tony Exp $")
!
      lgrav =.true.
      lgravx=.true.
      lgravx_gas =.true.
      lgravx_dust=.true.
!
    endsubroutine register_gravity
!***********************************************************************
    subroutine initialize_gravity()
!
!  Set up some variables for gravity; do nothing in grav_x
!
!  12-jun-04/axel: coded
!
      use CData
      use Mpicomm, only: stop_it
!
!  Different gravity profiles
!
      select case (grav_profile)

      case('const')
        if (lroot) print*,'initialize_gravity: constant gravx=',gravx
        gravx_pencil=gravx
        potx_pencil=-gravx*(x(l1:l2)-xinfty)
!
!  tanh profile
!  for isothermal EOS, we have 0=-cs2*dlnrho+gravx
!  pot_ratio gives the resulting ratio in the density.
!
      case('tanh')
        if (dgravx==0.) call stop_it("initialize_gravity: dgravx=0 not OK")
        if (lroot) print*,'initialize_gravity: tanh profile, gravx=',gravx
        if (lroot) print*,'initialize_gravity: xgrav,dgravx=',xgrav,dgravx
        gravx=-log(pot_ratio)/dgravx
        gravx_pencil=gravx*.5/cosh((x(l1:l2)-xgrav)/dgravx)**2
        potx_pencil=-gravx*.5*(1.+tanh((x(l1:l2)-xgrav)/dgravx))*dgravx

      case('sinusoidal')
        if (lroot) print*,'initialize_gravity: sinusoidal grav, gravx=',gravx
        gravx_pencil = -gravx*sin(kx_gg*x(l1:l2))

      case('kepler')
        if (lroot) print*,'initialize_gravity: kepler grav, gravx=',gravx
        gravx_pencil = -gravx/x(l1:l2)**2

      case default
        if (lroot) print*,'initialize_gravity: grav_profile not defined'

      endselect
!
    endsubroutine initialize_gravity
!***********************************************************************
    subroutine init_gg(f,xx,yy,zz)
!
!  initialise gravity; called from start.f90
!
!  12-jun-04/axel: adapted from grav_z
! 
      use Cdata
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: xx,yy,zz
!
! Not doing anything (this might change if we decide to store gg)
!
      if (NO_WARN) print*,f,xx,yy,zz !(keep compiler quiet)
!
    endsubroutine init_gg
!***********************************************************************
    subroutine calc_pencils_grav(f,p)
! 
!  Calculate gravity pencils
!
!  12-nov-04/anders: coded
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      type (pencil_case) :: p
!      
      intent(in) :: f
      intent(inout) :: p
!
      if (NO_WARN) print*, f, p
!
    endsubroutine calc_pencils_grav
!***********************************************************************
    subroutine duu_dt_grav(f,df,p)
!
!  add duu/dt according to gravity
!
!  12-jun-04/axel: adapted from grav_z
!
      use Cdata
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p

      integer :: k
!
      intent(in) :: f,p
      intent(out) :: df
!
!  Add gravity acceleration on gas and dust
!
      if (lhydro .and. lgravx_gas) &
          df(l1:l2,m,n,iux) = df(l1:l2,m,n,iux) + gravx_pencil
      if (ldustvelocity .and. lgravx_dust) then
        do k=1,ndustspec
          df(l1:l2,m,n,iudx(k)) = df(l1:l2,m,n,iudx(k)) + gravx_pencil
        enddo
      endif
!
      if (NO_WARN) print*,f,p !(keep compiler quiet)
!        
    endsubroutine duu_dt_grav
!***********************************************************************
    subroutine potential_global(xx,yy,zz,pot,pot0)
!
!  gravity potential
!
!  12-jun-04/axel: adapted from grav_z
!
      use Cdata, only: mx,my,mz
      use Mpicomm
!
      real, dimension (mx,my,mz) :: xx,yy,zz, pot
      real, optional :: pot0
!
      call stop_it("potential_global: not implemented for grav_x")
!
      if (NO_WARN) print*,xx(1,1,1)+yy(1,1,1)+zz(1,1,1), &
          pot(1,1,1),pot0  !(keep compiler quiet)
!
    endsubroutine potential_global
!***********************************************************************
    subroutine potential_penc(xmn,ymn,zmn,pot,pot0,grav,rmn)
!
!  calculates gravity potential and acceleration on a pencil
!
!  12-jun-04/axel: adapted from grav_z
!
      use Cdata, only: nx,lroot
!
      real, dimension (nx) :: pot,r
      real, optional :: ymn,zmn,pot0
      real, optional, dimension (nx) :: xmn,rmn
      real, optional, dimension (nx,3) :: grav
!
      real :: nu_epicycle2
      logical, save :: first=.true.
!
      intent(in) :: xmn,ymn,zmn,rmn
      intent(out) :: pot
!
!  identifier
!
      if (lroot.and.first) print*,'potential_penc: zinfty=',zinfty
!
!  the different cases are already precalculated in initialize_gravity
!
      pot=potx_pencil
!
!  prevent identifier from being called more than once
!
      first=.false.
!
    endsubroutine potential_penc
!***********************************************************************
    subroutine potential_point(x,y,z,r, pot,pot0, grav)
!
!  Gravity potential in one point
!
!  12-jun-04/axel: adapted from grav_z
!
      use Mpicomm, only: stop_it
!
      real :: pot,rad
      real, optional :: x,y,z,r
      real, optional :: pot0,grav
!
      call stop_it("grav_x: potential_point not implemented")
!
      if(NO_WARN) print*,x,y,z,r,pot,pot0,grav     !(to keep compiler quiet)
    endsubroutine potential_point
!***********************************************************************
    subroutine read_gravity_init_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat


      if (present(iostat)) then
        read(unit,NML=grav_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=grav_init_pars,ERR=99)
      endif




99    return
    endsubroutine read_gravity_init_pars
!***********************************************************************
    subroutine write_gravity_init_pars(unit)
      integer, intent(in) :: unit


      write(unit,NML=grav_init_pars)


    endsubroutine write_gravity_init_pars
!***********************************************************************
    subroutine read_gravity_run_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat


      if (present(iostat)) then
        read(unit,NML=grav_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=grav_run_pars,ERR=99)
      endif




99    return
    endsubroutine read_gravity_run_pars
!***********************************************************************
    subroutine write_gravity_run_pars(unit)
      integer, intent(in) :: unit
                                                                                  
      write(unit,NML=grav_run_pars)


    endsubroutine write_gravity_run_pars
!***********************************************************************
    subroutine rprint_gravity(lreset,lwrite)
!
!  reads and registers print parameters relevant for gravity advance
!  dummy routine
!
!  12-jun-04/axel: adapted from grav_z
!
      use Cdata
!
      logical :: lreset,lwr
      logical, optional :: lwrite
!
      lwr = .false.
      if (present(lwrite)) lwr=lwrite
!
!  write column, idiag_XYZ, where our variable XYZ is stored
!  idl needs this even if everything is zero
!
      if (lwr) then
        write(3,*) 'i_curlggrms=',idiag_curlggrms
        write(3,*) 'i_curlggmax=',idiag_curlggmax
        write(3,*) 'i_divggrms=',idiag_divggrms
        write(3,*) 'i_divggmax=',idiag_divggmax
        write(3,*) 'igg=',igg
        write(3,*) 'igx=',igx
        write(3,*) 'igy=',igy
        write(3,*) 'igz=',igz
      endif
!
      if(NO_WARN) print*,lreset  !(to keep compiler quiet)
    endsubroutine rprint_gravity
!***********************************************************************

endmodule Gravity
