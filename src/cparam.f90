! $Id: cparam.f90,v 1.41 2005-06-26 17:34:12 eos_merger_tony Exp $

module Cparam

!!!  Parameters

!  (nx,ny,nz) is the size of the computational mesh
!  The total nmumber of meshpoints is (nx*nprocx,ny*nprocy,nz*nprocz).
!  The number of ghost zones is NOT counted.
!
!  In practice, the user will change the number of cpus (in y and z)
!  and the number of mesh points, and recompile.
!  Dependening on what is invoked under Makefile.local,
!  one needs to adjust nvar.
!  This part is now isolated in a separate cparam.local file.
!
  include 'cparam.local'

! Need this kinda urgently!!
  integer, parameter :: nx=nxgrid,ny=nygrid/nprocy,nz=nzgrid/nprocz

  include 'cparam.inc'
  include 'cparam_pencils.inc'
!
!  derived and fixed parameters
!
  integer, parameter :: ikind8=selected_int_kind(14) ! 8-byte integer kind
  integer, parameter :: nghost=3
  integer(KIND=ikind8), parameter :: nw=nx*ny*nz
  integer, parameter :: mx=nx+2*nghost,l1=1+nghost,l2=mx-nghost
  integer, parameter :: my=ny+2*nghost,m1=1+nghost,m2=my-nghost
  integer, parameter :: mz=nz+2*nghost,n1=1+nghost,n2=mz-nghost
  integer, parameter :: mw=mx*my*mz,nwgrid=nxgrid*nygrid*nzgrid
!
  integer, parameter :: l1i=l1+nghost-1,l2i=l2-nghost+1
  integer, parameter :: m1i=m1+nghost-1,m2i=m2-nghost+1
  integer, parameter :: n1i=n1+nghost-1,n2i=n2-nghost+1
!
  integer, parameter :: nrcyl=nx/2 ! used for azimuthal averages
!
!  array dimension for reduce operation (maxima and sums)
!  use here symbol mreduce, use nreduce in call
!
  integer, parameter :: mreduce=6
  integer :: ip=14
!
!  length of file names
!            strings for boundary condition,
!            labels a la initss, initaa,
!            lines to be read in
!            date-and-time string
!
  integer, parameter :: fnlen=128,bclen=3,labellen=25,linelen=256,datelen=30
!
!  number of slots in initlnrho etc.
!
  integer, parameter :: ninit=4
!
!  significant length of random number generator state
!  Different compilers have different lengths:
!    NAG: 1, Compaq: 2, Intel: 47, SGI: 64, NEC: 256
  integer, parameter :: mseed=256
!
!  a marker value that is highly unlikely (``impossible'') to ever occur
!  during a meaningful run.
!  Maybe using NaN (how do you set this in F90?) would be better..
!
  real, parameter :: impossible=3.9085e37
!
!
! Diagnostic variable types 
!
!  Values > 0 get maxed across all  processors before any
!  transformation using mpi_reduce_max;
!  values < 0 get summed over all processors before any transformation
!  using mpi_reduce_sum;
!  value 0 causes the value simply to be used from the root processor 
!
  integer, parameter :: ilabel_max=-1,ilabel_sum=1,ilabel_save=0
  integer, parameter :: ilabel_max_sqrt=-2,ilabel_sum_sqrt=2
  integer, parameter :: ilabel_max_dt=-3,ilabel_max_neg=-4
  integer, parameter :: ilabel_max_reciprocal=-5
  integer, parameter :: ilabel_integrate=3,ilabel_surf=4
  integer, parameter :: ilabel_sum_par=5,ilabel_sum_sqrt_par=6
!
! physical constants, taken from:
! http://physics.nist.gov/cuu/Constants/index.html
  double precision, parameter :: hbar_cgs=1.054571596d-27  ! [erg*s]
  double precision, parameter :: R_cgs=8.3144D7            ! [erg/mol/K]
  double precision, parameter :: k_B_cgs=1.3806503d-16     ! [erg/K]
  double precision, parameter :: m_p_cgs=1.67262158d-24    ! [g]
  double precision, parameter :: m_e_cgs=9.10938188d-28    ! [g]
  double precision, parameter :: m_H_cgs=m_e_cgs+m_p_cgs   ! [g]
  double precision, parameter :: eV_cgs=1.602176462d-12    ! [erg]
  double precision, parameter :: sigmaSB_cgs=5.670400d-5   ! [erg/cm^2/s/K^4]
! unclear source (probably just guessing?)
  double precision, parameter :: sigmaH_cgs=4.d-17         ! [cm^2]
  double precision, parameter :: kappa_es_cgs=3.4d-1       ! [cm^2/g]
!
!
! Variable used in lines like:
!    if (NO_WARN) print*,uu
! which are added in dummy routines to prevent the compiler reporting
! unused arguments.  It is never intended that these print statements
! will ever actually get called. As a logical parameter however which
! is false, the compiler should infact optimise all such lines away.
!
  logical, parameter :: NO_WARN=.false.
!
!
endmodule Cparam

