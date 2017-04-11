!
! $Id: subcus.f,v 1.58 2010-03-08 17:46:45 georg Exp $
!
! simplified sedimentation module
!
! contents :
!
! subroutine simple_sedi	custom routines
!
! revision log :
!
! 03.02.2017	ggu	old routine copied from subcus.f
!
!******************************************************************

!==================================================================
	module simple_sediments
!==================================================================

	implicit none

	real, save, allocatable :: conzs(:)
	real, save, allocatable :: conza(:)
	real, save, allocatable :: conzh(:)
	integer, save, allocatable :: inarea(:)

	integer, save :: isimple = 1	!1 -> use module
	integer, save :: iout_area = -1	!area considered outside, -1 for none

	double precision, save :: da_out(4)	!index for output file

	real, save :: wsink = 5.e-4	!sinking velocity [m/s]
	real, save :: rhos = 2500.	!density of sediments [kg/m**3]
	real, save :: tce = 0.1		!critical threshold for erosion [N/m**2]
	real, save :: tcd = 0.03	!critical threshold for deposition [N/m**2]
	real, save :: eurpar = 1.e-3	!erosion parameter [kg/m**2/s]
	real, save :: z0 = 1.e-3	!roughness length [m]

!==================================================================
	end module simple_sediments
!==================================================================

        subroutine simple_sedi

! simplified sedimentation module

	use mod_conz
	use levels
	use basin
	use simple_sediments

        implicit none

	include 'femtime.h'

        integer ie,ii,k,lmax,l,ia
	integer iunit
        logical bnoret
        real vol,conz,perc,dt,sed,h,r,cnew
        double precision mass,masss
        double precision dtime,dtime0
        real volnode,depnode
	real getpar
	real caux(nlvdi)
	real taubot(nkn)
	real dc,f,tau

	integer iu,id,itmcon,idtcon,itstart
	save iu,id,itmcon,idtcon,itstart

        integer, save :: icall = 0

	if( icall < 0 ) return

!------------------------------------------------------------
! parameters
!------------------------------------------------------------

        bnoret = iout_area >= 0		!set concentrations out of domain to 0

	call get_timestep(dt)
	call getinfo(iunit)
	dtime = t_act

	if( tce < tcd ) stop 'error stop simple_sedi: tce < tcd'

!------------------------------------------------------------
! initialization
!------------------------------------------------------------

        if( icall .eq. 0 ) then

          write(6,*) 'initialization of routine sedimt: ',wsink

	  if( isimple <= 0 ) icall = -1
	  if( icall < 0 ) return

	  iconz = nint(getpar('iconz'))
	  if( iconz == 0 ) then
	    write(6,*) 'cannot run simple sediment module'
	    write(6,*) 'iconz == 0 but must be > 0'
	    stop 'error stop simple_sedi: iconz == 0'
	  end if

	  allocate(conzs(nkn))
	  allocate(conza(nkn))
	  allocate(conzh(nkn))
	  allocate(inarea(nkn))
	  conzs = 0.
	  conza = 0.
	  conzh = 0.
	  cnv = 0.

	  !itstart = nint(getpar('tcust'))

	  dtime0 = itanf
	  call simple_sedi_init_output
	  call simple_sedi_write_output(dtime0)

	  call in_area(iout_area,inarea)	!sets up array inarea

          icall = 1

        end if

!------------------------------------------------------------
! is it time ?
!------------------------------------------------------------

        !if( it .lt. itstart ) return

!------------------------------------------------------------
! sinking
!------------------------------------------------------------

          do k=1,nkn
	    lmax = ilhkv(k)
	    caux = 0
	    do l=1,lmax-1
              h = depnode(l,k,+1)
              vol = volnode(l,k,+1)
	      r = 0.
	      if( h .gt. 0. ) r = wsink/h
              conz = max(0.,cnv(l,k))
	      cnew = conz * exp(-r*dt)
	      dc = conz - cnew
	      caux(l) = caux(l) - dc
	      caux(l+1) = caux(l+1) + dc
	    end do
            h = depnode(lmax,k,+1)
	    tau = taubot(k)
	    call bottom_flux(k,tau,cnv(lmax,k),f)
	    dc = f * dt / h
	    caux(lmax) = caux(lmax) + dc
	    cnv(:,k) = cnv(:,k) + caux(:)
	    
	    conzs(k) = conzs(k) - vol*dc	! [kg]
	    conza(k) = conza(k) - h*dc		! [kg/m**2]
	    conzh(k) = conzh(k) - (h*dc)/rhos	! [m]
          end do

!------------------------------------------------------------
! total mass
!------------------------------------------------------------

        mass = 0.
        masss = 0.
        do k=1,nkn
            lmax = ilhkv(k)
            do l=1,lmax
              vol = volnode(l,k,+1)
              conz = cnv(l,k)
              mass = mass + vol*conz
            end do
	    masss = masss + conzs(k)
        end do

        write(6,*) 'sedimt: ',it,mass,masss,mass+masss
        write(iunit,*) 'sedimt: ',it,mass,masss,mass+masss

!------------------------------------------------------------
! write accumulated bottom sediments
!------------------------------------------------------------

	call simple_sedi_write_output(dtime)

!------------------------------------------------------------
! no return flow
!------------------------------------------------------------

        if( bnoret ) then
          do k=1,nkn
            if( inarea(k) .eq. 0 ) cnv(:,k) = 0.
          end do
        end if

!------------------------------------------------------------
! end of initialization
!------------------------------------------------------------

        end

!*****************************************************************

	subroutine in_area(iout_area,inarea)

! computes areas that are considered inside basin

	use basin

	implicit none

	integer iout_area
	integer inarea(nkn)

	integer ie,k,ii,ia

        inarea = 0

        do ie=1,nel
          ia = iarv(ie)
          if( ia .ne. iout_area ) then
              do ii=1,3
                k = nen3v(ii,ie)
                inarea(k) = 1
              end do
          end if
        end do

	end

!*****************************************************************

	subroutine bottom_flux(k,tau,conz,f)

! computes fluxes between bottom and water column

	use simple_sediments
	use mod_conz

	implicit none

	integer k	!node
	real tau	!bottom stress
	real conz	!concentration in last layer
	real f		!sediment flux, positive into water column [kg/m**2/s]

	if( tau < tcd ) then			!deposition
	  f = - ( 1. - tau/tcd ) * wsink * conz
	else if( tau > tce ) then		!erosion
	  f = eurpar * ( tau/tce - 1. )
	else					!nothing
	  f = 0.
	end if

	end

!*****************************************************************

	subroutine simple_sedi_init_output

	use simple_sediments

	implicit none

	integer, save :: nvar = 3
	integer id
	logical has_output_d

	da_out = 0

        call init_output_d('itmcon','idtcon',da_out)
        if( has_output_d(da_out) ) then
          call shyfem_init_scalar_file('ssed',nvar,.true.,id)
          da_out(4) = id
        end if

	end

!*****************************************************************

	subroutine simple_sedi_write_output(dtime)

	use simple_sediments

	implicit none

	double precision dtime

	integer id,idcbase
	logical next_output_d

        if( .not. next_output_d(da_out) ) return

        id = nint(da_out(4))
	idcbase = 21

        call shy_write_scalar_record(id,dtime,idcbase+1,1,conzs)	! [kg]
        call shy_write_scalar_record(id,dtime,idcbase+2,1,conza)	! [kg/m**2]
        call shy_write_scalar_record(id,dtime,idcbase+3,1,conzh)	! [m]

	end

!*****************************************************************

	subroutine simple_sedi_bottom_stress(taubot)

! must still integrate stress from waves

	use basin

	implicit none

	real taubot(nkn)

	real taucur(nkn)

	call bottom_stress(taucur)

	taubot = taucur

	end

!*****************************************************************
