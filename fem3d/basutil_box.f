
!--------------------------------------------------------------------------
!
!    Copyright (C) 2013,2015,2017-2019  Georg Umgiesser
!
!    This file is part of SHYFEM.
!
!    SHYFEM is free software: you can redistribute it and/or modify
!    it under the terms of the GNU General Public License as published by
!    the Free Software Foundation, either version 3 of the License, or
!    (at your option) any later version.
!
!    SHYFEM is distributed in the hope that it will be useful,
!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
!    GNU General Public License for more details.
!
!    You should have received a copy of the GNU General Public License
!    along with SHYFEM. Please see the file COPYING in the main directory.
!    If not, see <http://www.gnu.org/licenses/>.
!
!    Contributions to this file can be found below in the revision log.
!
!--------------------------------------------------------------------------

c revision log :
c
c 07.05.2013	ggu	copied from bastreat
c 14.05.2013	ggu	subroutines cleaned
c 10.10.2015	ggu	changed VERS_7_3_2
c 31.03.2017	ggu	changed VERS_7_5_24
c 22.02.2018	ggu	changed VERS_7_5_42
c 14.02.2019	ggu	changed VERS_7_5_56
c 16.02.2019	ggu	changed VERS_7_5_60
c 10.04.2021	ggu	better error handling and info output
c 10.11.2021	ggu	avoid warning for stack size
c 10.02.2022	ggu	better error message for not connected domain
c 16.02.2022	ggu	new routine basboxgrd()
c
c****************************************************************

        subroutine basbox

c reads grid with box information and writes index file boxes.txt

	use mod_geom
	use mod_depth
	use evgeom
	use basin
	use basutil

	implicit none

	!integer ndim

        character*60 line
	integer node,nit
	integer mode,np,n,niter,i
        integer ner,nco,nknh,nelh,nli
	integer nlidim,nlndim
	integer idepth
	integer nlkdi
	logical bstop

	integer, parameter :: nbxdim = 100	!max number of boxes
	integer, parameter :: nlbdim = 250	!max number of boundary nodes

	integer nbox
	integer nblink(nbxdim)
	integer, allocatable :: boxinf(:,:,:)
	integer neib(nbxdim)
	integer iaux1(2,nlbdim)
	integer iaux2(nlbdim)

c-----------------------------------------------------------------
c check if we have read a bas file and not a grd file
c-----------------------------------------------------------------

        if( .not. breadbas ) then
          write(6,*) 'for -box we need a bas file'
          stop 'error stop basbox: need a bas file'
        end if

c-----------------------------------------------------------------
c handle boxes
c-----------------------------------------------------------------

	allocate(boxinf(3,nlbdim,nbxdim))

	call check_box_connection

	call check_boxes(nbxdim,nbox,nblink)
	call handle_boxes(nbxdim,nlbdim,nbox,nblink,boxinf)

c-----------------------------------------------------------------
c write index file boxes.txt
c-----------------------------------------------------------------

	open(69,file='boxes.txt',form='formatted',status='unknown')

	call write_boxes(nbxdim,nlbdim,nbox,nblink,boxinf)
	call sort_boxes(nbxdim,nlbdim,nbox,nblink,boxinf,neib
     +			,iaux1,iaux2)

	close(69)

c-----------------------------------------------------------------
c end of routine
c-----------------------------------------------------------------

	write(6,*) 
	write(6,*) 'finished writing files'
	write(6,*) 'the index is in file boxes.txt'

	return
	end

c*******************************************************************
c*******************************************************************
c*******************************************************************

	subroutine sort_boxes(nbxdim,nlbdim,nbox,nblink,boxinf,neib
     +				,iaux1,iaux2)

c creates boxinf that contains information on sections
c boxinf(ii,n,ib)
c	ib is box number
c	n is an index of found intersections
c	ii=1	first node
c	ii=2	second node
c	ii=3	box number of neibor
c there are nblink(ib) node pairs in boxinf, so n=1,nblink(ib)

	use basin

	implicit none

	integer nbxdim,nlbdim,nbox
	integer nblink(nbxdim)
	integer boxinf(3,nlbdim,nbxdim)
	integer neib(nbxdim)
	integer iaux1(2,nlbdim)
	integer iaux2(nlbdim)
	integer ib,n,i,ii,ibn,nn,k
	integer jfill,j,ibb,nf,ns,nt,ntt
	integer id

	integer kantv(2,nkn)

	nt = 0
	ntt = 0
	id = 0
	do ib=1,nbox
	  neib(ib) = 0
	end do

	do k=1,nkn
	  kantv(1,k) = 0
	  kantv(2,k) = 0
	end do

	do ib=1,nbox
	  n = nblink(ib)
	  if( n .gt. 0 ) then
	    !write(6,*) '******** ',ib,n
	    do i=1,n
	      ibn = boxinf(3,i,ib)	!neibor box
	      neib(ibn) = neib(ibn) + 1
	    end do
	    !do ibn=1,nbox
	    do ibn=ib+1,nbox
	      nn = neib(ibn)
	      if( nn .gt. 0 ) then
		!write(6,*) '--- ',ib,ibn,nn
		neib(ibn) = 0
		jfill = 0
		do j=1,n
	          ibb = boxinf(3,j,ib)	!neibor box
		  if( ibn .eq. ibb ) then
		    jfill = jfill + 1
		    iaux1(1,jfill) = boxinf(1,j,ib)
		    iaux1(2,jfill) = boxinf(2,j,ib)
		  end if
		end do
		if( nn .ne. jfill ) then
			write(6,*) nn,jfill
			stop 'internal error'
		end if
		do j=1,jfill
		  !write(6,*) j,iaux1(1,j),iaux1(2,j)
		end do
		call sort_section(nlbdim,jfill,iaux1,nf,iaux2,nkn,kantv)
		!write(6,*) nf
		!write(6,*) (ipv(iaux2(i)),i=1,nf)

		call count_sections(nf,iaux2,ns)
		call invert_list(nf,iaux2)
		!write(66,*) ns,nf,ib,ibn
		!write(66,*) (ipv(iaux2(i)),i=1,nf)

		nt = nt + nf - ns + 1	!real nodes, no zeros
		ntt = ntt + nf + 1
		call write_section(nf,iaux2,id,ib,ibn,ipv)

	      end if
	    end do
	  end if
	end do

	write(69,*) 0,0,0,0
	write(6,*) 'total number of sections: ',id
	write(6,*) 'total number of nodes in sections: ',nt
	write(6,*) 'total number of needed nodes in sections: ',ntt

	end

c*******************************************************************

	subroutine sort_section(nlbdim,jfill,iaux1,nf,iaux2,nkn,kantv)

c given a list of points sorts the nodes to be continuous
c deals with sections that are not connected
c inserts between these connections a 0

	implicit none

	integer nlbdim,jfill
	integer iaux1(2,nlbdim)
	integer nf
	integer iaux2(nlbdim)
	integer nkn
	integer kantv(2,nkn)

	integer k,k1,k2,j,kk,kn,kstop

	nf = 0
	do k=1,nkn	!only test... can be deleted
	  if( kantv(1,k) .ne. 0 ) goto 99
	  if( kantv(2,k) .ne. 0 ) goto 99
	end do

	do j=1,jfill
	  k1 = iaux1(1,j)
	  k2 = iaux1(2,j)
	  kantv(1,k1) = k2
	  kantv(2,k2) = k1
	end do

	do k=1,nkn
	  if( kantv(2,k) .ne. 0 ) then
	    kk = k
	    kstop = k
	    do while( kantv(2,kk) .gt. 0 .and. kantv(2,kk) .ne. kstop )
	      kk = kantv(2,kk)
	    end do
	    do while( kk .gt. 0 )
	      nf = nf + 1
	      iaux2(nf) = kk
	      kn = kantv(1,kk)
	      kantv(1,kk) = 0
	      kantv(2,kk) = 0
	      kk = kn
	    end do
	    nf = nf + 1
	    iaux2(nf) = 0	!insert 0 between non-continuous connections
	  end if
	end do

	nf = nf - 1	!skip trailing 0

	do k=1,nkn	!only test... can be deleted
	  if( kantv(1,k) .ne. 0 ) goto 99
	  if( kantv(2,k) .ne. 0 ) goto 99
	end do

	return
   99	continue
	write(6,*) k,kantv(1,k),kantv(2,k)
	stop 'error stop sort_section: internal error'
	end

c*******************************************************************

	subroutine count_sections(n,list,ns)

	implicit none

	integer n
	integer list(n)
	integer ns

	integer i

	ns = 1
	do i=1,n
	  if( list(i) .eq. 0 ) ns = ns + 1
	end do

	end

c*******************************************************************

	subroutine write_section(n,list,id,ib,ibn,ipv)

	implicit none

	integer n
	integer list(n)
	integer id,ib,ibn
	integer ipv(*)

	integer i,j,is,ie,nn

	!write(6,*) 
	i = 1
	do while( i .le. n )
	  is = i
	  do while( list(i) .gt. 0 )
	    i = i + 1
	  end do
	  ie = i - 1
	  id = id + 1
	  nn = ie - is + 1
	  !write(68,*) id,nn,ib,ibn
	  !write(68,*) (ipv(list(j)),j=is,ie)
	  write(69,*) id,nn,ib,ibn
	  write(69,'((8i9))') (ipv(list(j)),j=is,ie)
	  i = i + 1
	end do

	end

c*******************************************************************

	subroutine invert_list(n,list)

	implicit none

	integer n
	integer list(n)

	integer i,j,iaux

	do i=1,n/2
	  j=n+1-i
	  iaux = list(i)
	  list(i) = list(j)
	  list(j) = iaux
	end do

	end

c*******************************************************************

	subroutine write_boxes(nbxdim,nlbdim,nbox,nblink,boxinf)

	use basin

	implicit none

	integer nbxdim,nlbdim,nbox
	integer nblink(nbxdim)
	integer boxinf(3,nlbdim,nbxdim)

	integer ib,n,i,ii,ie
	integer nu

	nu = 0

	do ib=1,nbox
	  n = nblink(ib)
	  if( n .gt. 0 ) then
	    nu = nu + 1
	    !write(6,*) ib,n
	    do i=1,n
	      !write(6,*) (boxinf(ii,i,ib),ii=1,3)
	    end do
	  end if
	end do

	!write(67,*) nel,nbox,nu
	!write(67,*) (iarv(ie),ie=1,nel)

	write(69,*) nel,nbox,nu
	write(69,'((8i9))') (iarv(ie),ie=1,nel)

	end

c*******************************************************************

	subroutine check_boxes(nbxdim,nbox,nblink)

	use mod_geom
	use basin

	implicit none

	integer nbxdim,nbox
	integer nblink(nbxdim)

	integer ib,ie,ien,ii,i1,i2
	integer ia,n,nb


	nbox = 0
	do ib=1,nbxdim
	  nblink(ib) = 0
	end do
	
	do ie=1,nel
	  ia = iarv(ie)
	  if( ia .le. 0 ) goto 99
	  if( ia .gt. nbxdim ) goto 99
	  nblink(ia) = nblink(ia) + 1
	  nbox = max(nbox,ia)
	end do

	nb = 0
	do ib=1,nbxdim
	  if( nblink(ib) .gt. 0 ) nb = nb + 1
	end do
	
	write(6,*) 'total number of boxes: ',nbox,nb

	return
   99	continue
	write(6,*) 'ia,nbxdim: ',ia,nbxdim
	stop 'error stop check_boxes: nbxdim'
	end

c*******************************************************************

	subroutine handle_boxes(nbxdim,nlbdim,nbox,nblink,boxinf)

c sets up box index

	use mod_geom
	use basin

	implicit none

	integer nbxdim			!box dimension
	integer nlbdim			!boundary node dimension 
	integer nbox			!total number of boxes (return)
	integer nblink(nbxdim)		!total number of boundary nodes for box
	integer boxinf(3,nlbdim,nbxdim)	!info for boundary nodes of box

	integer ib,ie,ien,ii,i1,i2
	integer ia,ian,n
	integer nboxes(nbxdim)

	nbox = 0
	nblink = 0
	nboxes = 0
	
	ian = 0

	do ie=1,nel
	  ia = iarv(ie)				!element type - is box number
	  if( ia .le. 0 ) goto 99
	  if( ia .gt. nbxdim ) goto 99
	  nboxes(ia) = nboxes(ia) + 1
	  nbox = max(nbox,ia)
	  do ii=1,3
	    ien = ieltv(ii,ie)
	    ian = 0
	    if( ien .gt. 0 ) ian = iarv(ien)
	    if( ian .gt. nbxdim ) goto 99
	    if( ien .gt. 0 .and. ian .ne. ia ) then  !neigbor is diff box
	      i1 = mod(ii,3) + 1
	      i2 = mod(ii+1,3) + 1
	      n = nblink(ia) + 1
	      if( n .gt. nlbdim ) goto 98
	      boxinf(1,n,ia) = nen3v(i1,ie)
	      boxinf(2,n,ia) = nen3v(i2,ie)
	      boxinf(3,n,ia) = ian
	      nblink(ia) = n
	    end if
	  end do
	end do

	write(6,*) 'box info:'
	write(6,*) ' box number    elements   bnd-nodes'
	do ia=1,nbox
	  write(6,*) ia,nboxes(ia),nblink(ia)
	end do

	return
   98	continue
	write(6,*) 'too many boundary nodes in box ',ia
	write(6,*) 'n,nlbdim: ',n,nlbdim
	write(6,*) 'increase nlbdim and recompile'
	stop 'error stop handle_boxes: nlbdim'
   99	continue
	write(6,*) 'too many boxes...'
	write(6,*) 'ia,ian,nbxdim: ',ia,ian,nbxdim
	write(6,*) 'increase nbxdim and recompile'
	stop 'error stop handle_boxes: nbxdim'
	end

c*******************************************************************
c*******************************************************************
c*******************************************************************

	subroutine check_box_connection

c checks if all boxes are connected

	use mod_geom
	use basin

	implicit none

	integer ie
	integer i,j,nc,ic,nt,nnocol
	integer icol,ierr,icolmax
	integer nmin,nmax
	integer icolor(nel)
	integer icon(nel)
	integer list(3,nel)	!insert not connected areas in this list

	integer ieext

	ic = 0
	ierr = 0
	icolmax = 0
	do ie=1,nel
	  icon(ie) = 0
	  icolor(ie) = 0
	end do

	do ie=1,nel
	  if( icon(ie) .eq. 0 ) then
	    ic = ic + 1
	    call color_box_area(ie,icon,icol,nc)
	    list(1,ic) = icol
	    list(2,ic) = nc
	    list(3,ic) = ie
	    !write(6,*) icol,nc
	    if( icol .gt. nel ) goto 99
	    if( icolor(icol) .ne. 0 ) then
	      !write(6,*) '*** area not connected: ',icol
	      ierr = ierr + 1
	    end if
	    icolor(icol) = icolor(icol) + nc
	    icolmax = max(icolmax,icol)
	  end if
	end do

	if( ierr > 0 ) then	!here error treatment for not connected areas
	 do i=1,ic
	  icol = list(1,i)
	  do j=i+1,ic
	    if( list(1,j) == icol ) then
		write(6,*) 'not connected area found ',icol
	        write(6,*) 'area            elements'
     +		// '   elem number (int)'
     +		// '   elem number (ext)'
		write(6,1123) list(:,i),ieext(list(3,i))
		write(6,1123) list(:,j),ieext(list(3,j))
	        ie = list(3,i)
	        if( list(2,i) > list(2,j) ) ie = list(3,j)
	        write(6,*) 'not connected area contains element (int/ext)'
     +			,ie,ieext(ie)
	    end if
	  end do
	 end do
	end if

	nnocol = count( icon == 0 )
	if( nnocol > 0 ) goto 96

	nt = 0
	ic = 0
	icol = 0
	nmin = nel
	nmax = 0
	do ie=1,nel
	  if( icolor(ie) .gt. 0 ) then
	    icol = ie
	    ic = ic + 1
	    nc = icolor(ie)
	    nmax = max(nmax,nc)
	    nmin = min(nmin,nc)
	    nt = nt + nc
	  end if
	end do
	
	if( ic /= icolmax ) goto 97

	write(6,*) 
	write(6,*) 'number of boxes: ',ic
	write(6,*) 'maximum box index: ',icol
	write(6,*) 'largest area contains element: ',nmax
	write(6,*) 'smallest area contains element: ',nmin
	write(6,*) 

	if( ierr /= 0 ) then
	  write(6,*) 'box number and number of elements: '
	  do icol=1,ic
	    write(6,*) icol,icolor(icol)
	  end do
	end if

	if( nel .ne. nt ) goto 98
	if( ierr .gt. 0 ) stop 'error stop check_box_connection: errors'

 1123	format(i5,3i20)
	return
   96	continue
	write(6,*) 'some elements could not be colored: ',nnocol
	write(6,*) 'the reason for this is unknown'
	stop 'error stop check_box_connection: could not color'
   97	continue
	write(6,*) 'ic,icolmax: ',ic,icolmax
	stop 'error stop check_box_connection: area numbers have holes'
   98	continue
	write(6,*) 'nel,nt: ',nel,nt
	stop 'error stop check_box_connection: internal error'
   99	continue
	write(6,*) 'icol = ',icol
	stop 'error stop check_box_connection: color code too high'
	end

c*******************************************************************

	subroutine color_box_area(iestart,icon,icol,nc)

c colors all accessible elements starting from iestart
c colors only elements with same area code
c uses this area code to color the elements
c area code 0 is not allowed !!!!

	use mod_geom
	use basin

	implicit none

	integer iestart
	integer icon(nel)
	integer icol		!color used (return)
	integer nc		!total number of elements colored (return)

	integer ip,ien,ii,ie
	integer list(nel)

	nc = 0
	ip = 1
	list(ip) = iestart
	icol = iarv(iestart)
	if( icol .le. 0 ) goto 98

	do while( ip .gt. 0 ) 
	  ie = list(ip)
	  if( icon(ie) .le. 0 ) nc = nc + 1
	  icon(ie) = icol
	  !write(6,*) icol,ip,ie
	  ip = ip -1
	  do ii=1,3
	    ien = ieltv(ii,ie)
	    if( ien .gt. 0 ) then
	      if( icon(ien) .eq. 0 .and. iarv(ien) .eq. icol ) then
	        ip = ip + 1
	        list(ip) = ien
	      end if
	    end if
	  end do
	end do

	return
   98	continue
	write(6,*) 'cannot color with icol < 1 : ',icol
	stop 'error stop color_box_area: iarv'
   99	continue
	write(6,*) ip,ie,ien,icol,icon(ien)
	stop 'error stop color_box_area: internal error (1)'
	end

!*******************************************************************
!*******************************************************************
!*******************************************************************
! here create grd file from index file
!*******************************************************************
!*******************************************************************
!*******************************************************************

	subroutine basboxgrd

	use basin
	use basutil

	implicit none

	integer ios
	integer ne,nbox,nmax
	integer ie,ia,itot
	integer, allocatable :: ibox(:),icount(:)

	write(6,*) 're-creating grd file from bas and index.txt'

        if( .not. breadbas ) then
          write(6,*) 'for -boxgrd we need a bas file'
          stop 'error stop basboxgrd: need a bas file'
        end if

	if( index_file == ' ' ) then
	  write(6,*) 'no index file given...'
	  stop 'error stop basboxgrd: no index file given'
	end if

	open(1,file=index_file,status='old',form='formatted',iostat=ios)
	if( ios /= 0 ) then
	  write(6,*) 'cannot open file: ',trim(index_file)
	  stop 'error stop basboxgrd: no such index file'
	end if
	write(6,*) 'reading index file...'

	read(1,*) ne,nbox,nmax
	write(6,*) nel,ne,nbox,nmax
	if( ne /= nel ) then
	  write(6,*) 'nel in basin and index file not compatible'
	  write(6,*) nel,ne
	  stop 'error stop basboxgrd: ne/= nel'
	end if

	allocate(ibox(ne),icount(0:nmax))
	read(1,*) ibox(1:ne)
	close(1)

	icount = 0
	do ie=1,ne
	  ia = ibox(ie)
	  if( ia < 0 .or. ia > nmax ) goto 99
	  icount(ia) = icount(ia) + 1
	end do

	itot = 0
	do ia=0,nmax
	  write(6,*) ia,icount(ia)
	  itot = itot + icount(ia)
	end do
	write(6,*) 'total: ',itot
	if( itot /= ne ) stop 'error stop basboxgrd: internal error (1)'
	
	iarv = ibox

        call basin_to_grd
        call grd_write('index.grd')
        write(6,*) 'The basin has been written to index.grd'

	return
   99	continue
	write(6,*) 'area code out of range: ',ia
	write(6,*) 'must be between 0 and ',nmax
	write(6,*) 'element is ie = ',ie
	stop 'error stop basboxgrd: out of range'
	end

!*******************************************************************

