
!==================================================================
	module mod_plot2d
!==================================================================

	implicit none

	integer, private, save  :: nkn_plot2d = 0
	integer, private, save  :: nel_plot2d = 0
	integer, private, save  :: np_plot2d = 0

	real, allocatable, save :: arfvlv(:)
	real, allocatable, save :: hetv(:)
	real, allocatable, save :: parray(:)

	logical, allocatable, save :: bwater(:)
	logical, allocatable, save :: bkwater(:)

!==================================================================
	contains
!==================================================================

	subroutine mod_plot2d_init(nkn,nel,np)

	integer nkn,nel,np

        if( nkn == nkn_plot2d .and. nel == nel_plot2d 
     +		.and. np == np_plot2d ) return

        if( nel > 0 .or. nkn > 0 .and. np > 0 ) then
          if( nel == 0 .or. nkn == 0 .and. np == 0 ) then
            write(6,*) 'nel,nkn,np: ',nel,nkn,np
            stop 'error stop mod_plot2d_init: incompatible parameters'
          end if
        end if

        if( nkn_plot2d > 0 ) then
          deallocate(arfvlv)
          deallocate(hetv)
          deallocate(parray)
          deallocate(bwater)
          deallocate(bkwater)
        end if

        nel_plot2d = nel
        nkn_plot2d = nkn
        np_plot2d = np

	if( nkn == 0 ) return

        allocate(arfvlv(nkn))
        allocate(hetv(nel))
        allocate(parray(np))
        allocate(bwater(nel))
        allocate(bkwater(nkn))

	end subroutine mod_plot2d_init

!==================================================================
	end module mod_plot2d
!==================================================================

