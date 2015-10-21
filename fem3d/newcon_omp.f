c
c revision log :
c
c 20.05.2015    erp     transformed for OMP
c 30.09.2015    ggu     routine cleaned, no reals in conz3d
c
c**************************************************************

        subroutine conz3d_omp(cn1,co1
     +			,ddt
     +                  ,rkpar,difhv,difv
     +			,difmol,cbound
     +		 	,itvd,itvdv,gradxv,gradyv
     +			,cobs,robs
     +			,wsink,wsinkv
     +			,rload,load
     +			,azpar,adpar,aapar
     +			,istot,isact,nlvddi,nlev)
c
c computes concentration
c
c cn     new concentration
c co     old concentration              !not used !FIXME
c caux   aux vector
c clow	 lower diagonal of vertical system
c chig	 upper diagonal of vertical system
c ddt    time step
c rkpar  horizontal turbulent diffusivity
c difhv  horizontal turbulent diffusivity (variable between elements)
c difv   vertical turbulent diffusivity
c difmol vertical molecular diffusivity
c cbound boundary condition (mass flux) [kg/s] -> now concentration [kg/m**3]
c itvd	 type of horizontal transport algorithm used
c itvdv	 type of vertical transport algorithm used
c gradxv,gradyv  gradient vectors for TVD algorithm
c cobs	 observations for nudging
c robs	 use observations for nuding (real)
c wsink	 factor for settling velocity
c wsinkv variable settling velocity [m/s]
c rload	 factor for loading
c load   load (source or sink) [kg/s]
c azpar  time weighting parameter
c adpar  time weighting parameter for vertical diffusion (ad)
c aapar  time weighting parameter for vertical advection (aa)
c istot	 total inter time steps
c isact	 actual inter time step
c nlvddi	 dimension in z direction
c nlv	 actual needed levels
c
c written 09.01.94 by ggu  (from scratch)
c revised 19.01.94 by ggu  $$flux - flux conserving property
c revised 20.01.94 by ggu  $$iclin - iclin not used to compute volume
c revised 20.01.94 by ggu  $$lumpc - evaluate conz. nodewise
c revised 03.02.94 by ggu  $$itot0 - exception for itot=0 or 3
c revised 04.02.94 by ggu  $$fact3 - factor 3 missing in transport
c revised 04.02.94 by ggu  $$azpar - azpar used to compute transport
c revised 04.02.94 by ggu  $$condry - comute conz also in dry areas
c revised 07.02.94 by ggu  $$istot - istot for fractional time step
c revised 01.06.94 by ggu  restructured for 3-d model
c revised 18.07.94 by ggu  $$htop - use htop instead of htopo for mass cons.
c revised 09.04.96 by ggu  $$rvadj adjust rv in certain areas
c
c solution of purely diffusional part :
c
c dC/dt = a*laplace(C)    with    c(x,0+)=delta(x)
c
c C(x,t) =  (4*pi*a*t)**(-n/2) * exp( -|x|**2/(4*a*t) )
c
c for n-dimensions and
c
c C(x,t) =  1/sqrt(4*pi*a*t) * exp( -x**2/(4*a*t) )
c
c for 1 dimension
c
c the solution is normalized, i.e.  int(C(x,t)dx) = 1 over the whole area
c
c DPGGU -> introduced double precision to stabilize solution

	use mod_bound_geom
	use mod_geom
	use mod_depth
	use mod_diff_aux
	use mod_bound_dynamic
	use mod_area
	use mod_ts
	use mod_hydro_vel
	use mod_hydro
	use evgeom
	use levels
	use basin
!$	use omp_lib
	use mod_subset

	implicit none

	integer, intent(in) :: nlvddi,nlev,itvd,itvdv,istot,isact
	real, intent(in) :: difmol,robs,wsink,rload,ddt,rkpar
	real, intent(in) :: azpar,adpar,aapar
	real,dimension(nlvddi,nkn),intent(inout) :: cn1
	real,dimension(nlvddi,nkn),intent(in) :: co1,difhv,cbound
	real,dimension(nlvddi,nkn),intent(in) :: gradxv,gradyv
	real,dimension(nlvddi,nkn),intent(in) :: cobs,load
	real,dimension(0:nlvddi,nkn),intent(in) :: difv,wsinkv
          
	logical :: btvdv
	integer :: ie,k,ilevel,ibase,ii,l,n,i,j,x,ies,iend,kl,kend
	integer :: myid,numthreads,j_init,j_end,k_init,k_end
	integer,allocatable,dimension(:) :: subset_l
	double precision :: dt
	double precision :: az,ad,aa,azt,adt,aat
	double precision :: rstot,rso,rsn,rsot,rsnt
	double precision :: timer,timer1,chunk,rest
	
	double precision,dimension(:,:),allocatable :: cn
	double precision,dimension(:,:),allocatable :: co        
        double precision,dimension(:,:),allocatable :: cdiag
	double precision,dimension(:,:),allocatable :: clow
	double precision,dimension(:,:),allocatable :: chigh

        if(nlv.ne.nlev) stop 'error stop conzstab: level'
	
c----------------------------------------------------------------
c initialize variables and parameters
c----------------------------------------------------------------

	ALLOCATE(cn(nlvddi,nkn))
	ALLOCATE(co(nlvddi,nkn))
	ALLOCATE(cdiag(nlvddi,nkn))
	ALLOCATE(clow(nlvddi,nkn))
	ALLOCATE(chigh(nlvddi,nkn))
	
	az = azpar
	ad = adpar
	aa = aapar
	
	azt=1.-az
	adt=1.-ad
	aat=1.-aa

	rstot = istot			!ERIC - what a brown paper bag bug
	rso=(isact-1)/rstot
	rsn=(isact)/rstot
	rsot=1.-rso
	rsnt=1.-rsn

	dt=ddt/istot
	
	btvdv = itvdv .gt. 0
	if( btvdv .and. aapar .ne. 0. ) then
	  write(6,*) 'aapar = ',aapar,'  itvdv = ',itvdv
	  write(6,*) 'Cannot use implicit vertical advection'
	  write(6,*) 'together with vertical TVD scheme.'
	  write(6,*) 'Please set either aapar = 0 (explicit) or'
	  write(6,*) 'itvdv = 0 (no vertical TVD) in the STR file.'
	  stop 'error stop conz3d: vertical tvd scheme'
	end if

	co=cn1
        cn=0.
        cdiag=0.
        clow=0.
        chigh=0.
 
!$OMP PARALLEL  DEFAULT(NONE) 
!$OMP& PRIVATE(i,j,k,ie,timer,timer1,myid,numthreads)
!$OMP& PRIVATE(chunk,rest,j_init,j_end,k_init,k_end)
!$OMP& SHARED(nlvddi,nlev,itvd,itvdv,istot,isact,aa)
!$OMP& SHARED(difmol,robs,wsink,rload,ddt,rkpar,az,ad)
!$OMP& SHARED(azt,adt,aat,rso,rsn,rsot,rsnt,dt,nkn)
!$OMP& SHARED(cn,co,cdiag,clow,chigh,subset_el,cn1,co1) 
!$OMP& SHARED(subset_num,indipendent_subset) 
!$OMP& SHARED(difhv,cbound,gradxv,gradyv,cobs,load,difv,wsinkv) 

       myid = 0
!$     myid = omp_get_thread_num()		!ERIC
       numthreads = 1
!$     numthreads = omp_get_num_threads()

      do i=1,subset_num 	! loop over indipendent subset
 
       chunk = subset_el(i) / numthreads
       rest  = MOD(subset_el(i),numthreads) 
       j_init = (myid * chunk)+1
       j_end = j_init + chunk-1
       if(myid .eq. numthreads-1) j_end = subset_el(i)

       do j=j_init,j_end 	! loop over elements in subset
	        ie = indipendent_subset(j,i)
	        
                call conz3d_element(ie,cdiag,clow,chigh,cn,cn1
     +			,dt
     +                  ,rkpar,difhv,difv
     +			,difmol,cbound
     +		 	,itvd,itvdv,gradxv,gradyv
     +			,cobs,robs
     +			,wsink,wsinkv
     +			,rload,load
     +			,az,ad,aa,azt,adt,aat
     +			,rso,rsn,rsot,rsnt
     +			,nlvddi,nlev)
   
	end do ! end loop over el in subset
      
!$OMP BARRIER        

       end do ! end loop over subset
       	
       chunk = nkn / numthreads
       rest  = MOD(nkn,numthreads) 
       k_init = (myid * chunk)+1
       k_end = k_init + chunk-1
       if(myid .eq. numthreads-1) k_end = nkn

       do k=k_init,k_end

	   call conz3d_nodes(k,cn,cdiag(:,k),clow(:,k),chigh(:,k),
     +                          cn1,cbound,load,rload,
     +                          ad,aa,dt,nlvddi)
 	      
	end do

!$OMP END PARALLEL 

	!cn1 = 0.
	!cn1 = cn
	cn1 = real(cn)

	DEALLOCATE(cn)
	DEALLOCATE(co)
	DEALLOCATE(cdiag)
	DEALLOCATE(clow)
	DEALLOCATE(chigh)
	
c----------------------------------------------------------------
c end of routine
c----------------------------------------------------------------

	end

c*****************************************************************

       subroutine conz3d_element(ie
     +			,cdiag,clow,chigh,cn,cn1
     +			,dt
     +                  ,rkpar,difhv,difv
     +			,difmol,cbound
     +		 	,itvd,itvdv,gradxv,gradyv
     +			,cobs,robs
     +			,wsink,wsinkv
     +			,rload,load
     +			,az,ad,aa,azt,adt,aat
     +			,rso,rsn,rsot,rsnt
     +			,nlvddi,nlev)
     
        use mod_bound_geom
	use mod_geom
	use mod_depth
	use mod_diff_aux
	use mod_bound_dynamic
	use mod_area
	use mod_ts
	use mod_hydro_vel
	use mod_hydro
	use evgeom
	use levels
	use basin
	use mod_layer_thickness
      
      implicit none
      
      integer,intent(in) :: ie,nlvddi,nlev,itvd,itvdv
      real,intent(in) :: difmol,robs,wsink,rload,rkpar
      real,dimension(nlvddi,nkn),intent(in) :: cn1,difhv,cbound
      real,dimension(nlvddi,nkn),intent(in) :: gradxv,gradyv,cobs,load
      real,intent(in),dimension(0:nlvddi,nkn) :: wsinkv,difv
      double precision,intent(in) :: dt
      double precision,intent(in) :: az,ad,aa,azt,adt,aat
      double precision,intent(in) :: rso,rsn,rsot,rsnt
      double precision,dimension(nlvddi,nkn),intent(inout) :: cdiag
      double precision,dimension(nlvddi,nkn),intent(inout) :: clow
      double precision,dimension(nlvddi,nkn),intent(inout) :: chigh
      double precision,dimension(nlvddi,nkn),intent(inout) :: cn
        
        logical :: btvdv,btvd,bgradup
	integer :: k,ii,l,iii,ll,ibase,lstart,ilevel,itot,isum
	integer :: n,i,iext
	integer, dimension(3) :: kn
        double precision :: cexpl,cbm,ccm,waux,loading,wws,us,vs
        double precision :: aj,rk3,aj4,aj12
        double precision :: hmed,hmbot,hmtop,hmotop,hmobot
        double precision :: hmntop,hmnbot,rvptop,rvpbot,w,aux
        double precision :: flux_tot,flux_tot1,flux_top,flux_bot
        double precision :: rstot,hn,ho,cdummy,alow,adiag,ahigh
        double precision :: rkmin,rkmax,cconz
      double precision,dimension(:),allocatable :: fw,fd,fl,fnudge
      double precision,dimension(:),allocatable :: b,c,f,wdiff
      double precision,dimension(:),allocatable :: hdv,haver,presentl
      double precision,dimension(:,:),allocatable :: hnew,htnew,rtau,cob
      double precision,dimension(:,:),allocatable :: hold,htold,vflux,wl
      double precision,dimension(:,:),allocatable :: cl
      double precision,dimension(:,:),allocatable :: clc,clm,clp,cle
	
	if(nlv.ne.nlev) stop 'error stop conzstab: level'

! ----------------------------------------------------------------
!  initialize variables and parameters
! ----------------------------------------------------------------

	btvd = itvd .gt. 0
	bgradup = itvd .eq. 2	!use upwind gradient for tvd scheme
	btvdv = itvdv .gt. 0

	wws = 0.

! ----------------------------------------------------------------
! global arrays for accumulation of implicit terms
! ----------------------------------------------------------------

	 ALLOCATE(fw(3),fd(3),fl(3),fnudge(3),wdiff(3))
	 ALLOCATE(b(3),c(3),f(3))
	 ALLOCATE(hdv(0:nlvddi+1),haver(0:nlvddi+1))
	 ALLOCATE(presentl(0:nlvddi+1))
	 ALLOCATE(hnew(0:nlvddi+1,3),htnew(0:nlvddi+1,3))
	 ALLOCATE(rtau(0:nlvddi+1,3),cob(0:nlvddi+1,3))
	 ALLOCATE(hold(0:nlvddi+1,3),htold(0:nlvddi+1,3))
	 ALLOCATE(vflux(0:nlvddi+1,3),wl(0:nlvddi+1,3))
	 ALLOCATE(cl(0:nlvddi+1,3))
	 ALLOCATE(clc(nlvddi,3),clm(nlvddi,3))
	 ALLOCATE(clp(nlvddi,3),cle(nlvddi,3))
	 
          hdv = 0.		!layer thickness
          haver = 0.
	  presentl = 0.		!1. if layer is present
	  hnew = 0.		!as hreal but with zeta_new
	  hold = 0.		!as hreal but with zeta_old
	  cl = 0.		!concentration in layer
	  wl = 0.		!vertical velocity
	  vflux = 0.		!vertical flux
	
!	these are the local arrays for accumulation of implicit terms
!	(maybe we do not need them, but just to be sure...)
!	after accumulation we copy them onto the global arrays

	    cle = 0.
	    clc = 0.
	    clm = 0.
	    clp = 0.
      
	do ii=1,3
          k=nen3v(ii,ie)
	  kn(ii)=k
	  b(ii)=ev(ii+3,ie)
	  c(ii)=ev(ii+6,ie)
	end do

	aj=ev(10,ie)    !area of triangle / 12
	aj4=4.*aj
	aj12=12.*aj
        ilevel=ilhv(ie)

! 	----------------------------------------------------------------
! 	set up vectors for use in assembling contributions
! 	----------------------------------------------------------------

        do l=1,ilevel
	  hdv(l) = hdeov(l,ie)		!use old time step -> FIXME
          !haver(l) = 0.5 * ( hdeov(l,ie) + hdenv(l,ie) )
          haver(l) = rso*hdenv(l,ie) + rsot*hdeov(l,ie)
	  presentl(l) = 1.
	  do ii=1,3
	    k=kn(ii)
	    hn = hdknv(l,k)		! there are never more layers in ie
	    ho = hdkov(l,k)		! ... than in k
            htold(l,ii) = ho
            htnew(l,ii) = hn
	    hold(l,ii) = rso * hn + rsot * ho
	    hnew(l,ii) = rsn * hn + rsnt * ho
	    cl(l,ii) = cn1(l,k)
	    cob(l,ii) = cobs(l,k)	!observations
	    rtau(l,ii) = rtauv(l,k)	!observations
	    wl(l,ii) = wlnv(l,k) - wsink * wsinkv(l,k)
	  end do
	end do

	do l=ilevel+1,nlv
	  presentl(l) = 0.
	end do

! 	----------------------------------------------------------------
! 	set vertical velocities in surface and bottom layer
! 	----------------------------------------------------------------
! 
! 	we do not set wl(0,ii) because otherwise we loose concentration
! 	through surface
! 
! 	we set wl(ilevel,ii) to 0 because we are on the bottom
! 	and there should be no contribution from this element
! 	to the vertical velocity

	do ii=1,3
	  wl(ilevel,ii) = 0.
	end do

! 	----------------------------------------------------------------
! 	compute vertical fluxes (w/o vertical TVD scheme)
! 	----------------------------------------------------------------

	call vertical_flux_ie(btvdv,ie,ilevel,dt,wws,cl,wl,hold,vflux)

! ----------------------------------------------------------------
!  loop over levels
! ----------------------------------------------------------------

        do l=1,ilevel

        us=az*utlnv(l,ie)+azt*utlov(l,ie)             !$$azpar
        vs=az*vtlnv(l,ie)+azt*vtlov(l,ie)

        rk3 = 3. * rkpar * difhv(l,ie)

	cbm=0.
	ccm=0.
	itot=0
	isum=0
	do ii=1,3
	  k=kn(ii)
	  f(ii)=us*b(ii)+vs*c(ii)	!$$azpar
	  if(f(ii).lt.0.) then	!flux out of node
	    itot=itot+1
	    isum=isum+ii
	  end if
	  cbm=cbm+b(ii)*cl(l,ii)
	  ccm=ccm+c(ii)*cl(l,ii)

! 	  ----------------------------------------------------------------
! 	  initialization to be sure we are in a clean state
! 	  ----------------------------------------------------------------

	  fw(ii) = 0.
	  !cle(l,ii) = 0.	!ERIC
	  !clc(l,ii) = 0.
	  !clm(l,ii) = 0.
	  !clp(l,ii) = 0.

! 	  ----------------------------------------------------------------
! 	  contributions from horizontal diffusion
! 	  ----------------------------------------------------------------

          waux = 0.
          do iii=1,3
            waux = waux + wdifhv(iii,ii,ie) * cl(l,iii)
          end do
          wdiff(ii) = waux

! 	  ----------------------------------------------------------------
! 	  contributions from vertical diffusion
! 	  ----------------------------------------------------------------
! 
! 	  in fd(ii) is explicit contribution
! 	  the sign is for the term on the left side, therefore
! 	  fd(ii) must be subtracted from the right side
! 
! 	  maybe we should use real layer thickness, or even the
! 	  time dependent layer thickness

	  rvptop = difv(l-1,k) + difmol
	  rvpbot = difv(l,k) + difmol
	  !hmtop = 2. * rvptop * presentl(l-1) / (hdv(l-1)+hdv(l))
	  !hmbot = 2. * rvpbot * presentl(l+1) / (hdv(l)+hdv(l+1))
	  hmotop =2.*rvptop*presentl(l-1)/(hold(l-1,ii)+hold(l,ii))
	  hmobot =2.*rvpbot*presentl(l+1)/(hold(l,ii)+hold(l+1,ii))
	  hmntop =2.*rvptop*presentl(l-1)/(hnew(l-1,ii)+hnew(l,ii))
	  hmnbot =2.*rvpbot*presentl(l+1)/(hnew(l,ii)+hnew(l+1,ii))

	  fd(ii) = adt * ( 
     +			(cl(l,ii)-cl(l+1,ii))*hmobot -
     +			(cl(l-1,ii)-cl(l,ii))*hmotop
     +			  )

	  clc(l,ii) = clc(l,ii) + ad * ( hmntop + hmnbot )
	  clm(l,ii) = clm(l,ii) - ad * ( hmntop )
	  clp(l,ii) = clp(l,ii) - ad * ( hmnbot )

! 	  ----------------------------------------------------------------
! 	  contributions from vertical advection
! 	  ----------------------------------------------------------------
! 
! 	  in fw(ii) is explicit contribution
! 	  the sign is for the term on the left side, therefore
! 	  fw(ii) must be subtracted from the right side
! 
! 	  if we are in last layer, w(l,ii) is zero
! 	  if we are in first layer, w(l-1,ii) is zero (see above)

	  w = wl(l-1,ii) - wws		!top of layer
	  if( l .eq. 1 ) w = 0.		!surface -> no transport (WZERO)
	  if( w .ge. 0. ) then
	    fw(ii) = aat*w*cl(l,ii)
	    flux_top = w*cl(l,ii)
	    clc(l,ii) = clc(l,ii) + aa*w
	  else
	    fw(ii) = aat*w*cl(l-1,ii)
	    flux_top = w*cl(l-1,ii)
	    clm(l,ii) = clm(l,ii) + aa*w
	  end if

	  w = wl(l,ii) - wws		!bottom of layer
	  if( l .eq. ilevel ) w = 0.	!bottom -> handle flux elsewhere (WZERO)
	  if( w .gt. 0. ) then
	    fw(ii) = fw(ii) - aat*w*cl(l+1,ii)
	    flux_bot = w*cl(l+1,ii)
	    clp(l,ii) = clp(l,ii) - aa*w
	  else
	    fw(ii) = fw(ii) - aat*w*cl(l,ii)
	    flux_bot = w*cl(l,ii)
	    clc(l,ii) = clc(l,ii) - aa*w
	  end if

	  flux_tot1 = aat * ( flux_top - flux_bot )
	  flux_tot = aat * ( vflux(l-1,ii) - vflux(l,ii) )

	  fw(ii) = flux_tot
	end do

! 	----------------------------------------------------------------
! 	contributions from horizontal advection (only explicit)
! 	----------------------------------------------------------------
! 
! 	f(ii) > 0 ==> flux into node ii
! 	itot=1 -> flux out of one node
! 		compute flux with concentration of this node
! 	itot=2 -> flux into one node
! 		for flux use conz. of the other two nodes and
! 		minus the sum of these nodes for the flux of this node

	if(itot.eq.1) then	!$$flux
	  fl(1)=f(1)*cl(l,isum)
	  fl(2)=f(2)*cl(l,isum)
	  fl(3)=f(3)*cl(l,isum)
	else if(itot.eq.2) then
	  isum=6-isum
	  fl(1)=f(1)*cl(l,1)
	  fl(2)=f(2)*cl(l,2)
	  fl(3)=f(3)*cl(l,3)
	  fl(isum) = 0.
	  fl(isum) = -(fl(1)+fl(2)+fl(3))
	  isum=6-isum		!reset to original value
	else			!exception	$$itot0
	  fl(1)=0.
	  fl(2)=0.
	  fl(3)=0.
	end if

! 	----------------------------------------------------------------
! 	horizontal TVD scheme start
! 	----------------------------------------------------------------

        if( btvd ) then
	  iext = 0
	  do ii=1,3
	    k = nen3v(ii,ie)
	    if( is_external_boundary(k) ) iext = iext + 1
	  end do

          if( iext .eq. 0 ) then
	    call tvd_fluxes(ie,l,itot,isum,dt,cl,cn1,gradxv,gradyv,f,fl)
	  end if
	end if

! 	----------------------------------------------------------------
! 	horizontal TVD scheme finish
! 	----------------------------------------------------------------

! 	----------------------------------------------------------------
! 	contributions from nudging
! 	----------------------------------------------------------------

	do ii=1,3
	  fnudge(ii) = robs * rtau(l,ii) * ( cob(l,ii) - cl(l,ii) )
	end do

! 	----------------------------------------------------------------
! 	sum explicit contributions
! 	----------------------------------------------------------------

	do ii=1,3
	  k=kn(ii)
          hmed = haver(l)                    !new ggu   !HACK
	  cexpl = aj4 * ( hold(l,ii)*cl(l,ii)
     +				+ dt *  ( 
     +					    hold(l,ii)*fnudge(ii)
     +					  + 3.*fl(ii) 
     +					  - fw(ii)
     +					  - rk3*hmed*wdiff(ii)
     +					  - fd(ii)
     +					)
     +			               )
	  
	  !clm(1,ii) = 0.		!ERIC
	  !clp(ilevel,ii) = 0.
	  ! next check to be deleted
	  if( clm(1,ii) /= 0. .or. clp(ilevel,ii) /= 0. ) then
	    write(6,*) ie,ii,ilevel
	    write(6,*) clm(1,ii),clp(ilevel,ii)
	    stop 'error stop: assumption violated'
	  end if
	  
	  alow  = aj4 * dt * clm(l,ii)
	  ahigh = aj4 * dt * clp(l,ii)
	  adiag = aj4 * dt * clc(l,ii) + aj4 * hnew(l,ii)
	  cn(l,k)    = cn(l,k)    + cexpl
	  clow(l,k)  = clow(l,k)  + alow
	  chigh(l,k) = chigh(l,k) + ahigh   
          cdiag(l,k) = cdiag(l,k) + adiag
	   
	end do

	end do		! loop over l
	
! ----------------------------------------------------------------
!  end of loop over l
! ----------------------------------------------------------------

	deallocate(fw,fd,fl,fnudge)
	deallocate(b,c,f,wdiff)
	deallocate(hdv,haver,presentl)
	deallocate(hnew,htnew,rtau,cob)
	deallocate(hold,htold,vflux,wl,cl)
	deallocate(clc,clm,clp,cle)
	
! ----------------------------------------------------------------
!  end of routine
! ----------------------------------------------------------------

      end subroutine conz3d_element

! *****************************************************************
      
       subroutine conz3d_nodes(k,cn,cdiag,clow,chigh,cn1,cbound,
     +                         load,rload,ad,aa,dt,nlvddi)

      	use mod_bound_geom
	use mod_geom
	use mod_depth
	use mod_diff_aux
	use mod_bound_dynamic
	use mod_area
	use mod_ts
	use mod_hydro_vel
	use mod_hydro
	use evgeom
	use levels
	use basin
	
	implicit none
	
	integer,intent(in) :: k,nlvddi
	real,intent(in) :: rload
	real,dimension(nlvddi,nkn),intent(in) :: cn1,cbound,load
	double precision, intent(in) :: dt
	double precision, intent(in) :: ad,aa

	double precision,dimension(nlvddi,nkn),intent(inout) :: cn
	double precision,dimension(nlvddi),intent(inout) :: cdiag
	double precision,dimension(nlvddi),intent(inout) :: clow
	double precision,dimension(nlvddi),intent(inout) :: chigh

	integer :: l,ilevel,lstart,i,ii,ie,n,ibase
	double precision :: mflux,qflux,cconz
	double precision :: loading,aux

	double precision, parameter :: d_tiny = tiny(1.d+0)
	double precision, parameter :: r_tiny = tiny(1.)
      
! ----------------------------------------------------------------
!  handle boundary (flux) conditions
! ----------------------------------------------------------------

      	  ilevel = ilhkv(k)

	  do l=1,ilevel
            !mflux = cbound(l,k)		!mass flux has been passed
	    cconz = cbound(l,k)		!concentration has been passed
	    qflux = mfluxv(l,k)
	    if( qflux .lt. 0. .and. is_boundary(k) ) cconz = cn1(l,k)
	    mflux = qflux * cconz

            cn(l,k) = cn(l,k) + dt * mflux	!explicit treatment

	    loading = rload*load(l,k)
            if( loading .eq. 0. ) then
	      !nothing
	    else if( loading .gt. 0. ) then    		!treat explicit
              cn(l,k) = cn(l,k) + dt * loading
            else !if( loading .lt. 0. ) then		!treat quasi implicit
	      if( cn1(l,k) > 0. ) then
                cdiag(l) = cdiag(l) - dt * loading/cn1(l,k)
	      end if
            end if
	  end do

! ----------------------------------------------------------------
!  compute concentration for each node (solve system)
! ----------------------------------------------------------------

	if((aa .eq. 0. .and. ad .eq. 0.).or.(nlv .eq. 1)) then

	if( nlv .gt. 1 ) then
	  write(6,*) 'conz: computing explicitly ',nlv
	end if

	!do k=1,nkn
	 ilevel = ilhkv(k)
	 do l=1,ilevel
	  if(cdiag(l).ne.0.) then
	    cn(l,k)=cn(l,k)/cdiag(l)
	  end if
	 end do

	else

	  ilevel = ilhkv(k)
	  aux=1./cdiag(1)
	  chigh(1)=chigh(1)*aux
	  cn(1,k)=cn(1,k)*aux
	  do l=2,ilevel
	    aux=1./(cdiag(l)-clow(l)*chigh(l-1))
	    chigh(l)=chigh(l)*aux
	    cn(l,k)=(cn(l,k)-clow(l)*cn(l-1,k))*aux
	  end do
	  lstart = ilevel-1
	  do l=lstart,1,-1	!$$LEV0 bug 14.08.1998 -> ran to 0
	    cn(l,k)=cn(l,k)-cn(l+1,k)*chigh(l)
	  end do
	end if
	
! ----------------------------------------------------------------
!  end of routine
! ----------------------------------------------------------------

      end subroutine conz3d_nodes

c*****************************************************************

