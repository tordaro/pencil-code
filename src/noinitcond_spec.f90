!  $Id: noinitcond_spec.f90,v 1.9 2005-06-26 17:34:13 eos_merger_tony Exp $
!
!  Substitute routines for vortex_solve.f90
!
!  This is a dummy module for absorb calls to initial condition routines
!  that are not checked in as part of the code. In the present case, the
!  real routines are checked in somewhere under pencil-anders.
!  Decoupling this from the main part of the code is useful if the
!  routine becomes excessively complicated and a burden to read.
!  It also lowers potential problems with compiler errors.
!  The name Initcond_spec is sufficiently general so that other complicated
!  initial condition algorithms could well be checked in here.

module Initcond_spec

  implicit none

  private

  public :: kepvor, enthblob

  contains

!***********************************************************************
    subroutine kepvor(f,xx,yy,zz,b_ell,q_ell,gamma,cs20,hh0)
!
!   4-apr-03/anders: coded
!
      use Cdata
      use General
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: xx,yy,zz
      real :: q_ell, b_ell, hh0
      real :: gamma,cs20
      if(NO_WARN) print*,f,xx,yy,zz,b_ell,q_ell,gamma,cs20,hh0 ! compiler quiet
    endsubroutine kepvor
!***********************************************************************
    subroutine enthblob(f,xx,yy,zz,b_ell,q_ell,gamma,cs20,hh0)
!
!  17-may-03/anders: coded
!
      use Cdata
      use General
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: xx,yy,zz
      real :: q_ell, b_ell, hh0
      real :: gamma,cs20
      if(NO_WARN) print*,f,xx,yy,zz,b_ell,q_ell,gamma,cs20,hh0 ! compiler quiet
    endsubroutine enthblob

endmodule Initcond_spec
