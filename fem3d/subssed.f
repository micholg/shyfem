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
! 09.05.2017	ggu	some bugs fixed
!
! notes :
!
! in order to run the module set issedi=1 in the STR file, $para section
! output frequency is according to itmcon, idtcon
! files written are with extension .ssed.shy
!
!******************************************************************

!==================================================================
	module simple_sediments
!==================================================================

	implicit none

	real, save, allocatable :: conzs(:)	!bottom sediment [kg]
	real, save, allocatable :: conza(:)	!bottom sediment [kg/m**2]
	real, save, allocatable :: conzh(:)	!bottom sediment [m]
	real, save, allocatable :: sedflux(:)	!sediment flux [kg/m**2/s]
	integer, save, allocatable :: inarea(:)	!0 if area out of basin

! sediment flux is positive from sediment into water column

	logical, save :: bssedi = .false.	!is running?

	integer, save :: issedi = 0	!1 -> use module (set in STR file)
	integer, save :: iout_area = -1	!area considered outside, -1 for none

	double precision, save :: da_out(4)	!index for output file

	real, save :: wsink = 5.e-4	!sinking velocity [m/s]
	real, save :: rhos = 2500.	!density of sediments [kg/m**3]
	real, save :: tce = 0.1		!critical threshold erosion [N/m**2]
	real, save :: tcd = 0.03	!critical threshold deposition [N/m**2]
	real, save :: eurpar = 1.e-3	!erosion parameter [kg/m**2/s]

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
	real dc,f,tau,alpha
	real cmin,cmax,ccc

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
	call get_act_dtime(dtime)

	if( tce < tcd ) stop 'error stop simple_sedi: tce < tcd'

!------------------------------------------------------------
! initialization
!------------------------------------------------------------

        if( icall .eq. 0 ) then

          issedi = nint(getpar('issedi'))
          if( issedi .le. 0 ) icall = -1
          if( icall .le. -1 ) return
          icall = 1

          write(6,*) 'initialization of routine sedimt: ',issedi

	  if( iconz /= 1 ) then
	    write(6,*) 'cannot run simple sediment module'
	    write(6,*) 'iconz must be == 1'
	    stop 'error stop simple_sedi: iconz /= 1'
	  end if

	  allocate(conzs(nkn))
	  allocate(conza(nkn))
	  allocate(conzh(nkn))
	  allocate(sedflux(nkn))
	  allocate(inarea(nkn))
	  conzs = 0.
	  conza = 0.
	  conzh = 0.
	  sedflux = 0.
	  cnv = 0.

	  !itstart = nint(getpar('tcust'))

	  call get_first_dtime(dtime0)
	  call simple_sedi_init_output
	  call simple_sedi_write_output(dtime0)

	  call in_area(iout_area,inarea)	!sets up array inarea

          icall = 1
	  bssedi = .true.

          write(6,*) 'finished initialization of routine sedimt'
        end if

!------------------------------------------------------------
! is it time ?
!------------------------------------------------------------

        !if( it .lt. itstart ) return

!------------------------------------------------------------
! sinking
!------------------------------------------------------------

	  call bottom_stress(taubot)

 	  cmax = maxval(cnv)

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
            vol = volnode(lmax,k,+1)
	    tau = taubot(k)
	    r = dt/h
	    call bottom_flux(k,tau,cnv(lmax,k),r,alpha,f) !f is sediment flux
	    sedflux(k) = f
	    dc = f * dt / h
	    caux(lmax) = caux(lmax) + dc
		ccc = cnv(1,k)
	    cnv(:,k) = cnv(:,k) + caux(:)

	    conzs(k) = conzs(k) - vol*dc	! [kg]
	    conza(k) = conza(k) - h*dc		! [kg/m**2]
	    conzh(k) = conzh(k) - (h*dc)/rhos	! [m]

            !write(6,*) conzs(k),conza(k),conzh(k),f,'simple_sed_b_s'
	    !if( k == 100 ) write(6,*) k,tau,cnv(lmax,k),f,dc
          end do

	cmin = minval(cnv)
	cmax = maxval(cnv)
	!write(6,*) cmin,cmax

	where( cnv < 0. ) cnv = 0.

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

        !write(6,*) 'sedimt: ',dtime,mass,masss,mass+masss
        write(iunit,*) 'sedimt: ',dtime,mass,masss,mass+masss

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

	subroutine bottom_flux(k,tau,conz,r,alpha,f)

! computes fluxes between bottom and water column

	use simple_sediments
	use mod_conz

	implicit none

	integer k	!node
	real tau	!bottom stress
	real conz	!concentration in last layer
	real alpha	!flux factor [dimensionless]
	real r		!factor for exponential deposition (dt/h)
	real f		!sediment flux, positive into water column [kg/m**2/s]

	real dc

	if( tau < tcd ) then			!deposition
	  alpha = - ( 1. - tau/tcd )
	  dc = conz*(exp(alpha*r*wsink)-1.)
	  f = dc / r
	  !f = alpha * wsink * conz
	else if( tau > tce ) then		!erosion
	  alpha = ( tau/tce - 1. )
	  f = alpha * eurpar
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

        call shy_write_scalar_record(id,dtime,idcbase+1,1,conzs) ! [kg]
        call shy_write_scalar_record(id,dtime,idcbase+2,1,conza) ! [kg/m**2]
        call shy_write_scalar_record(id,dtime,idcbase+3,1,conzh) ! [m]

	end

!*****************************************************************

	subroutine get_sediment_values(k,flux,conz)

	use levels
	use mod_conz
	use simple_sediments

	implicit none

	integer k	 !node
	real flux	 !sediment flux at node k [kg/m**2/s]
	real conz(nlvdi) !sediment concentration in water column [kg/m**3]

	if( .not. bssedi ) then
	  write(6,*) 'bssedi: ',bssedi
	  stop 'error stop get_sediment_values: sediments not running'
	end if

	flux = sedflux(k)
	conz(:) = cnv(:,k)

	end

!*****************************************************************

