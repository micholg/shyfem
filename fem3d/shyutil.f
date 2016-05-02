!
! utilities for SHY files
!
! revision log :
!
! 29.04.2010    ggu     new file from nosaver
! 07.05.2010    ggu     new routines qopen_nos_file(), checks ev initialization
! 15.12.2010    ggu     volume computation also for sigma layers
! 10.11.2011    ggu     new routines for hybrid levels, init_volume() changed
! 02.12.2011    ggu     bug fix for call to get_sigma_info() (missing argument)
! 10.02.2012    ggu     new routines to get initial/final time of records
! 25.01.2013    ggu     new routines nos_get_vars()
! 05.09.2013    ggu     new call to get_layer_thickness()
! 20.01.2014    ggu     new helper routines
! 23.09.2015    ggu     close files in nos_get_it_start() nos_get_it_end()
!
!***************************************************************

!==================================================================
	module shyutil
!==================================================================

	implicit none

        real, save, allocatable :: vol3e(:,:)
        real, save, allocatable :: vol3k(:,:)
        real, save, allocatable :: areae(:)
        real, save, allocatable :: areak(:)

        real, save, allocatable :: shy_znv(:)
        real, save, allocatable :: shy_zenv(:,:)
        real, save, allocatable :: shy_zeta(:)

        integer, save, allocatable :: naccu(:,:)
        double precision, save, allocatable :: accum(:,:,:,:)
        double precision, save, allocatable :: std(:,:,:,:)
        double precision, save, allocatable :: dir(:,:,:,:,:)

        integer, parameter :: idir = 16
        real, parameter :: adir = 360. / idir

	logical, save :: bzeta = .false.

!==================================================================
	contains
!==================================================================

	subroutine shyutil_init(nkn,nel,nlv)

	integer nkn,nel,nlv

	allocate(vol3e(nlv,nel))
	allocate(vol3k(nlv,nkn))
	allocate(areae(nel))
	allocate(areak(nkn))

	allocate(shy_znv(nkn))
	allocate(shy_zenv(3,nel))
	allocate(shy_zeta(nel))

	vol3e = 1.
	vol3k = 1.
	areae = 1.
	areak = 1.

	shy_znv = 0.
	shy_zenv = 0.
	shy_zeta = 0.

	end subroutine shyutil_init

!***************************************************************

	subroutine shyutil_init_accum(nlv,nn,nvar,istep)

	integer nlv,nn,nvar,istep

        allocate(naccu(0:nvar,istep))
        allocate(accum(nlv,nn,0:nvar,istep))
        allocate(std(nlv,nn,0:nvar,istep))

	naccu = 0.
	accum = 0.
	std = 0.

	end subroutine shyutil_init_accum

!***************************************************************

	subroutine shyutil_init_dir(nlv,nn,nvar,istep)

	integer nlv,nn,nvar,istep

        allocate(dir(nlv,nn,idir,0:nvar,istep))

	dir = 0.

	end subroutine shyutil_init_dir

!==================================================================
	end module shyutil
!==================================================================

	subroutine shy_make_vert_aver(idims,nndim,cv3,cv2)

	use basin
	use levels
	use shyutil

	implicit none

	integer idims(4)
	integer nndim
	real cv3(nlvdi,nndim)
	real cv2(nndim)

	integer ivar,lmax,nn,ie
	real cmin,cmax,cmed,vtot
	real vol2(nndim)

        ivar = idims(4)
        lmax = idims(3)
        nn = idims(1) * idims(2)

	if( lmax == 1 ) then
	  cv2(:) = cv3(1,:)
	else if( ivar == 3 ) then	!transports - must sum
	  do ie=1,nel
	    cv2(ie) = sum( cv3(1:ilhv(ie),ie) )
	  end do
	else
	  if( nn == nkn ) then
	    call make_aver_3d(nlvdi,nn,cv3,vol3k,ilhkv
     +				,cmin,cmax,cmed,vtot,cv2,vol2)
	  else if( nn == nel ) then
	    call make_aver_3d(nlvdi,nn,cv3,vol3e,ilhv
     +				,cmin,cmax,cmed,vtot,cv2,vol2)
	  else
	    write(6,*) ivar,nn,nkn,nel
	    stop 'error stop shy_make_vert_aver: not possible'
	  end if
	end if

	end

!***************************************************************

	subroutine shy_make_basin_aver(idims,nndim,cv3
     +				,cmin,cmax,cmed,vtot)

	use basin
	use levels
	use shyutil

	implicit none

	integer idims(4)
	integer nndim
	real cv3(nlvdi,nndim)
	real cmin,cmax,cmed,vtot

	integer ivar,lmax,nn
	real ze(3*nel)
	real zaux(nel)
	real cv2(nndim)
	real vol2(nndim)

        ivar = idims(4)
        lmax = idims(3)
        nn = idims(1) * idims(2)

	if( abs(ivar) == 1 ) then		! water level - 2D
	  if( lmax /= 1 ) then
	    write(6,*) ivar,nn,lmax,nkn,nel
	    stop 'error stop shy_make_basin_aver: level must have lmax=1'
	  end if
	  if( nn == nkn ) then
	    call make_aver_2d(nlvdi,nn,cv3,areak
     +				,cmin,cmax,cmed,vtot)
	  else if( nn == nel ) then
	    call make_aver_2d(nlvdi,nn,cv3,areae
     +				,cmin,cmax,cmed,vtot)
	  else if( nn == 3*nel ) then			!zenv
	    ze(:) = cv3(1,:)
	    call shy_make_zeta_from_elem(nel,ze,zaux)
	    call make_aver_2d(nlvdi,nel,zaux,areae
     +				,cmin,cmax,cmed,vtot)
	  else
	    write(6,*) ivar,nn,nkn,nel
	    stop 'error stop shy_make_basin_aver: not possible'
	  end if
	else
	  if( nn == nkn ) then
	    call make_aver_3d(nlvdi,nn,cv3,vol3k,ilhkv
     +				,cmin,cmax,cmed,vtot,cv2,vol2)
	  else if( nn == nel ) then
	    call make_aver_3d(nlvdi,nn,cv3,vol3e,ilhv
     +				,cmin,cmax,cmed,vtot,cv2,vol2)
	  else
	    write(6,*) ivar,nn,nkn,nel
	    stop 'error stop shy_make_basin_aver: not possible'
	  end if
	end if

	end

!***************************************************************

	subroutine make_aver_2d(nlvddi,nn,cv3,area
     +				,cmin,cmax,cmed,vtot)

	implicit none

	integer nlvddi
	integer nn
	real cv3(nlvddi,nn)
	real area(nn)
	real cmin,cmax,cmed,vtot

	integer i
	double precision c,v
	double precision cctot,vvtot

	cmin = cv3(1,1)
	cmax = cv3(1,1)
	cctot = 0.
	vvtot = 0.

	do i=1,nn
	    c = cv3(1,i)
	    v = area(i)
	    cmin = min(cmin,c)
	    cmax = max(cmax,c)
	    cctot = cctot + c*v
	    vvtot = vvtot + v
	end do

	cmed = cctot / vvtot
	vtot = vvtot

	end

!***************************************************************

	subroutine make_aver_3d(nlvddi,nn,cv3,vol,il
     +				,cmin,cmax,cmed,vtot,cv2,vol2)

	implicit none

	integer nlvddi
	integer nn
	real cv3(nlvddi,nn)
	real vol(nlvddi,nn)
	integer il(nn)
	real cmin,cmax,cmed,vtot
	real cv2(nn)
	real vol2(nn)

	integer i,l,lmax
	double precision c,v
	double precision cctot,vvtot
	double precision c2tot,v2tot
        integer :: ks = 3096
        logical bdebug

	cmin = cv3(1,1)
	cmax = cv3(1,1)
	cctot = 0.
	vvtot = 0.

	do i=1,nn
	  lmax = il(i)
	  c2tot = 0.
	  v2tot = 0.
	  bdebug = i == ks
	  do l=1,lmax
	    c = cv3(l,i)
	    v = vol(l,i)
	    cmin = min(cmin,c)
	    cmax = max(cmax,c)
	    c2tot = c2tot + c*v
	    v2tot = v2tot + v
	    if( bdebug ) write(41,*) l,v,c
	  end do
	  cv2(i) = c2tot / v2tot
	  vol2(i) = v2tot
	  cctot = cctot + c2tot
	  vvtot = vvtot + v2tot
	  if( bdebug ) write(41,*) lmax,v2tot,c2tot,cv2(i)
	end do

	cmed = cctot / vvtot
	vtot = vvtot

	end

!***************************************************************
!***************************************************************
!***************************************************************

	subroutine shy_make_zeta(ftype)

	use basin
	use shyutil

	implicit none

	integer ftype

	if( ftype == 1 ) then
	  call shy_make_zeta_from_elem(nel,shy_zenv,shy_zeta)
	else if( ftype == 2 ) then
	  call shy_make_zeta_from_node(nkn,nel,nen3v,shy_znv,shy_zeta)
	else
	  shy_zeta = 0.
	end if

	end

!***************************************************************

	subroutine shy_make_zeta_from_node(nkn,nel,nen3v,znv,zeta)

	implicit none

	integer nkn,nel
	integer nen3v(3,nel)
	real znv(nkn)
	real zeta(nel)

	integer ie,k,ii
	real z

	do ie=1,nel
	  z = 0.
	  do ii=1,3
	    k = nen3v(ii,ie)
	    z = z + znv(k)
	  end do
	  zeta(ie) = z / 3.
	end do

	end

!***************************************************************

	subroutine shy_make_zeta_from_elem(nel,zenv,zeta)

	implicit none

	integer nel
	real zenv(3,nel)
	real zeta(nel)

	integer ie,ii
	real z

	do ie=1,nel
	  z = 0.
	  do ii=1,3
	    z = z + zenv(ii,ie)
	  end do
	  zeta(ie) = z / 3.
	end do

	end

!***************************************************************
!***************************************************************
!***************************************************************

	subroutine shy_make_area

! computes area of elements

	use basin
	use evgeom
	use shyutil

	implicit none

	logical binit
	integer ie,ii,k
	real area

	call is_init_ev(binit)
	if( .not. binit ) then
	  stop 'error stop shy_make_area: ev not initialized'
	end if

	areak = 0.

	do ie=1,nel
	  area = 4. * ev(10,ie)
	  do ii=1,3
	    k = nen3v(ii,ie)
	    areak(k) = areak(k) + area
	  end do
	  areae(ie) = 3. * area
	end do

	end

!***************************************************************

	subroutine shy_make_volume

! initializes volumes

	use basin
	use shyutil
	use levels
	use mod_depth

	implicit none

	logical bvolwrite,bdebug
	integer ie,ii,k,l,lmax,nsigma,nlvaux,ks
	real z,h,hsigma
	double precision ak,vk,ve
	double precision, allocatable :: vole(:,:),volk(:,:)
	real hl(nlv)		!aux vector for layer thickness

	bvolwrite = .false.
	bvolwrite = .true.
	ks = 2985
	ks = 3096

        call get_sigma_info(nlvaux,nsigma,hsigma)

	vol3e = 0.
	vol3k = 0.
	allocate(vole(nlvdi,nel))
	allocate(volk(nlvdi,nkn))
	vole = 0.
	volk = 0.

	do ie=1,nel
	  ak = areae(ie) / 3.	!area of vertex
	  z = shy_zeta(ie)
	  h = hev(ie)
	  lmax = ilhv(ie)
	  call get_layer_thickness(lmax,nsigma,hsigma,z,h,hlv,hl)
	  do l=1,lmax
	    vk = ak * hl(l)
	    ve = 3. * vk
	    vole(l,ie) = vole(l,ie) + ve
	    do ii=1,3
	      k = nen3v(ii,ie)
	      bdebug = k == ks
	      volk(l,k) = volk(l,k) + vk
	      if( bdebug ) write(81,*) ie,ii,lmax,l,vk,ak,hl(l),h
	    end do
	  end do
	  if( bvolwrite .and. mod(ie,nel/nel) == -1 ) then
	    write(61,*) ie,h
	    write(61,*) hl
	  end if
	end do

	vol3e = vole
	vol3k = volk

	deallocate(vole,volk)

	if( nlv <= 1 ) bvolwrite = .false.
	if( bvolwrite ) then
	write(71,*) 'volume from shy_make_volume'
	do k=1,nkn,nkn/10
	  write(71,*) k
	  write(71,*) vol3k(:,k)
	end do
	end if

	end

!***************************************************************
!***************************************************************
!***************************************************************

	subroutine shy_time_aver(mode,iv,nread,ifreq,istep,nndim
     +				,idims,threshold,cv3,bout)

! mode:  1:aver  2:sum  3:min  4:max  5:std  6:rms  7:thres  8:averdir
!
! mode negative: only transform, do not accumulate

	use basin
	use shyutil
	use levels

	implicit none

	integer mode
	integer iv
	integer nread,ifreq,istep
	integer nndim
	integer idims(4)
	double precision threshold
	real cv3(nlvdi,nndim)
	logical bout

	integer ip,naccum,mmode
	integer k,l,id,idmax
	integer ivar,lmax,nn
	double precision dmax

	if( mode .eq. 0 ) return

! either istep == 1 or ifreq == 0

	bout = .false.
	ip = mod(nread,istep)
	if( ip .eq. 0 ) ip = istep

        ivar = idims(4)
        lmax = idims(3)
        nn = idims(1) * idims(2)

	!write(6,*) 'ip: ',ip,istep,nread,mode

	if( mode == 1 .or. mode == 2 ) then
	  accum(:,:,iv,ip) = accum(:,:,iv,ip) + cv3(:,:)
	else if( mode == 3 ) then
	  accum(:,:,iv,ip) = min(accum(:,:,iv,ip),cv3(:,:))
	else if( mode == 4 ) then
	  accum(:,:,iv,ip) = max(accum(:,:,iv,ip),cv3(:,:))
	else if( mode == 5 ) then
	  accum(:,:,iv,ip) = accum(:,:,iv,ip) + cv3(:,:)
	  std(:,:,iv,ip) = std(:,:,iv,ip) + cv3(:,:)**2
	else if( mode == 6 ) then
	  accum(:,:,iv,ip) = accum(:,:,iv,ip) + cv3(:,:)**2
	else if( mode == 7 ) then
	  where( cv3(:,:) >= threshold )
	    accum(:,:,iv,ip) = accum(:,:,iv,ip) + 1.
	  end where
	else if( mode == 8 ) then
	  do k=1,nn
	    do l=1,lmax
	      id = nint( cv3(l,k)/adir )
	      if( id == 0 ) id = idir
	      if( id < 0 .or. id > idir ) stop 'error stop: direction'
	      dir(l,k,id,iv,ip) = dir(l,k,id,iv,ip) + 1.
	    end do
	  end do
	end if

	if( mode > 0 ) naccu(iv,ip) = naccu(iv,ip) + 1
	!write(6,*) '... ',ifreq,mode,ip,istep,naccu(iv,ip)

	if( naccu(iv,ip) == ifreq .or. mode < 0 ) then
	  naccum = max(1,naccu(iv,ip))
	  mmode = abs(mode)
	  if( mmode == 3 ) naccum = 1			!min
	  if( mmode == 4 ) naccum = 1			!max
	  if( mmode == 7 ) naccum = 1			!threshold
	  if( naccum > 0 ) cv3(:,:) = accum(:,:,iv,ip)/naccum
	  if( mmode == 5 ) then
	    cv3(:,:) = sqrt( std(:,:,iv,ip)/naccum - cv3(:,:)**2 )
	  else if( mmode == 6 ) then
	    cv3(:,:) = sqrt( cv3(:,:) )
	  else if( mmode == 8 ) then
	    do k=1,nn
	      do l=1,lmax
		dmax = 0.
		idmax = 0
	        do id=1,idir
		  if( dir(l,k,id,iv,ip) > dmax ) then
		    idmax = id
		    dmax = dir(l,k,id,iv,ip)
		  end if
		end do
		if( idmax == idir ) idmax = 0
		cv3(l,k) = idmax * adir
	      end do
	    end do
	  end if
	  write(6,*) 'averaging: ',ip,naccum,naccu(iv,ip)
	  bout = .true.
	  naccu(iv,ip) = 0
	  accum(:,:,iv,ip) = 0.
	  std(:,:,iv,ip) = 0.
	  if( allocated(dir) ) dir(:,:,:,iv,ip) = 0.
	end if

	end

!***************************************************************
!***************************************************************
!***************************************************************

        subroutine transp2vel_new(nel,nkn,nlv,nlvddi,hev,zenv,nen3v
     +                          ,ilhv,hlv,utlnv,vtlnv
     +                          ,uprv,vprv)

c transforms transports at elements to velocities at nodes

        implicit none

        integer nel
        integer nkn
        integer nlv
        integer nlvddi
        real hev(nel)
        real zenv(3,nel)
        integer nen3v(3,nel)
        integer ilhv(nel)
        real hlv(nlvddi)
        real utlnv(nlvddi,nel)
        real vtlnv(nlvddi,nel)
        real uprv(nlvddi,nkn)
        real vprv(nlvddi,nkn)

        real weight(nlvddi,nkn)         !aux variable for weights
        real hl(nlvddi)                 !aux variable for real level thickness

        logical bsigma
        integer ie,ii,k,l,lmax,nsigma,nlvaux
        real hmed,u,v,area,zeta
        real hsigma

        real area_elem

        call get_sigma_info(nlvaux,nsigma,hsigma)
        if( nlvaux .gt. nlvddi ) stop 'error stop transp2vel: nlvddi'
        bsigma = nsigma .gt. 0

	weight = 0.
	uprv = 0.
	vprv = 0.

        do ie=1,nel

          area = area_elem(ie)
          lmax = ilhv(ie)
          call compute_levels_on_element_new(ie,zenv,zeta)
	  call get_layer_thickness(lmax,nsigma,hsigma,zeta,hev(ie),hlv,hl)
          !call get_layer_thickness_e(ie,lmax,bzeta,nsigma,hsigma,hl)

          do l=1,lmax
            hmed = hl(l)
            u = utlnv(l,ie) / hmed
            v = vtlnv(l,ie) / hmed
            do ii=1,3
              k = nen3v(ii,ie)
              uprv(l,k) = uprv(l,k) + area * u
              vprv(l,k) = vprv(l,k) + area * v
              weight(l,k) = weight(l,k) + area
            end do
          end do
        end do

	where( weight > 0. )
	  uprv = uprv / weight
	  vprv = vprv / weight
	end where

        end

c******************************************************************

        subroutine compute_levels_on_element_new(ie,zenv,zeta)

        implicit none

        integer ie
        real zenv(3,*)
        real zeta

        integer ii
        real z

        z = 0.
        do ii=1,3
          z = z + zenv(ii,ie)
        end do

        zeta = z / 3.

        end

c******************************************************************

