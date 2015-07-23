#!/bin/bash

nsites=4
nstates="$(echo "$((4**$nsites))")"
echo "module routines

	implicit none

	integer, parameter :: sp = kind(1.0)      !single precison kind
	integer, parameter :: dp = kind(1.0d0)    !double precision kind
	real(dp) :: grand_potential_ground=0.0_dp                 ! the lowest grand ensemble energy
	integer, parameter :: nsites = $nsites
	integer, parameter :: total_states = $nstates
	integer, parameter :: int_kind = 4
	integer, parameter :: STDOUT = 10

	integer, dimension(2,total_states) :: fock_states
	integer, dimension(0:2**nsites) :: states_order
	integer :: ne
	integer :: total_states_up
	integer, dimension(nsites,total_states) :: PES_down=0, PES_up=0, IPES_down=0, IPES_up=0  !matrices for PES and IPES 
	integer, dimension(nsites,total_states) :: phase_PES_down=0, phase_PES_up=0, phase_IPES_down=0, phase_IPES_up=0  !to get anticommutation sign right

	real(dp), dimension(total_states) :: grand_potential      ! grand potentials (eigenenergies - mu*number electrons)
	real(dp), dimension(total_states,total_states) :: eigenvectors                  ! the eigenvectors
	integer, dimension(0:nsites) :: block, temp_block
	integer, dimension(0:nsites) :: nstates_up
	integer, allocatable, dimension(:,:) :: neighbours
	integer, dimension(0:nsites,0:nsites) :: msize, mblock
	"

for ((n_up=0; n_up<=nsites; n_up++)); do
	echo -n "	real(dp) :: "
	for ((n_dn=0; n_dn<=nsites; n_dn++)); do
		term1="$(echo -e "$nsites \n $n_up"| ./math.e)"
		term2="$(echo -e "$nsites \n $n_dn"| ./math.e)"
		final="$(echo "$(($term1*$term2))")"
		echo -n "H$n_up$n_dn($final,$final)"
		if [[ $n_dn != $nsites ]]; then
			echo -n ","
		fi
	done
	echo ""
done

echo "
contains

	!------------------------------------------------------

	subroutine random_gen_seed()

	  implicit none

	  integer :: seed_size, clock, i
	  integer, allocatable, dimension(:) :: seed

	  call random_seed(size=seed_size)
	  allocate(seed(seed_size))
	  call system_clock(count = clock)
	  seed=clock + 37*(/(i-1,i=1,seed_size)/)
	  call random_seed(put=seed)
	  deallocate(seed)

	end subroutine random_gen_seed

	!------------------------------------------------------

	subroutine site_potentials(delta,E)

	  implicit none

	  real(dp), intent(in) :: delta
	  real(dp), intent(out) :: E(nsites)
	  real :: random
	  integer :: i ! counter

	  do i=1,nsites
	     call random_number(random)              ! gives a random number between 0 and 1
	     E(i) = delta*(random - 0.5_dp)          ! centers the random numbers about 0
	  end do

	end subroutine site_potentials

	!------------------------------------------------------

	subroutine num_sites()

		implicit none

		integer :: i,j, istate, isite

		integer :: max_electrons

		total_states_up = 2**nsites
		max_electrons = nsites

		block = 0  
	    nstates_up = 0
	    block(0) = 1
	    nstates_up(0) = 1

		do ne = 1, max_electrons
       		nstates_up(ne) = choose(nsites,ne)          ! number of spin-up fock states with ne electrons
       		block(ne) = block(ne-1) + nstates_up(ne-1) ! block index updating
    	end do

    	temp_block = block

		do istate=0,total_states_up-1
			ne = 0
			do isite=1,nsites
				ne = ne + ibits(istate,isite-1,1)     ! count the number of electrons in that state
			end do 
			states_order(temp_block(ne)) = istate
			temp_block(ne) = temp_block(ne) + 1
		end do

		istate = 1
		do ne=0,max_electrons
			do j=1,total_states_up
				do i=block(ne), block(ne) + nstates_up(ne) - 1
					fock_states(1,istate) = states_order(i)
					fock_states(2,istate) = states_order(j)
					istate = istate + 1
				end do
			end do
		end do

	end subroutine num_sites

	!------------------------------------------------------

	subroutine transformations()

		implicit none
		
		integer :: i,j,new_state(2), new_index, position, isite

		PES_up = 0; PES_down = 0
	    IPES_up = 0; IPES_down = 0
	    phase_PES_up = 0; phase_PES_down = 0
	    phase_IPES_up = 0; phase_IPES_down = 0

		! make the PES_up matrices

		do position = 1,nsites
			do i=1,total_states
				ne = 0
				if (ibits(fock_states(1,i),position-1,1) == 1) then
					PES_up(position,i) = 0
					phase_PES_up(position,i) = 0 
				else
					do isite=position,nsites
						ne = ne + ibits(fock_states(1,i),isite-1,1)     ! count the number of up electrons in that state
						end do
					do isite=position,nsites
						ne = ne + ibits(fock_states(2,i),isite-1,1)     ! count the number of down electrons in that state
					end do
					if (MOD(ne,2) == 0) then 
						phase_PES_up(position,i) = 1
					else
						phase_PES_up(position,i) = -1
					end if
					new_state(1) = ibset(fock_states(1,i),position-1)
					new_state(2) = fock_states(2,i)
					do j=1,total_states
						if(fock_states(1,j) == new_state(1) .and. fock_states(2,j) == new_state(2)) then
							new_index = j
						end if
					end do
					PES_up(position,i) = new_index
				end if
			end do
		end do

		do position = 1,nsites
			do i=1,total_states
				ne = 0
				if (ibits(fock_states(2,i),position-1,1) == 1) then
					PES_down(position,i) = 0
					phase_PES_down(position,i) = 0 
				else
					do isite=position+1,nsites
						ne = ne + ibits(fock_states(1,i),isite-1,1)     ! count the number of up electrons in that state
					end do
					do isite=position,nsites
						ne = ne + ibits(fock_states(2,i),isite-1,1)     ! count the number of down electrons in that state
					end do
					if (MOD(ne,2) == 0) then 
						phase_PES_down(position,i) = 1
					else
						phase_PES_down(position,i) = -1
					end if
					new_state(2) = ibset(fock_states(2,i),position-1)
					new_state(1) = fock_states(1,i)
					do j=1,total_states
						if(fock_states(1,j) == new_state(1) .and. fock_states(2,j) == new_state(2)) then
							new_index = j
						end if
					end do
					PES_down(position,i) = new_index
				end if
			end do
		end do

		sites: do j=1,nsites  ! calculating the IPES matrices by making them the opposite of the PES
         do i=1,total_states
            if (PES_down(j,i) /= 0) then
               phase_IPES_down(j,PES_down(j,i)) = phase_PES_down(j,i)
               IPES_down(j,PES_down(j,i)) = i
            end if
            if (PES_up(j,i) /= 0) then
               IPES_up(j,PES_up(j,i)) = i
               phase_IPES_up(j,PES_up(j,i)) = phase_PES_up(j,i)
            end if
         end do
      end do sites

	end subroutine transformations

	!-------------------------------------------------------

	subroutine make_neighbours()

	! makes matrix that containes information about which sites are nearest neighbours
	! neighbours(i,:) is a list of all the neighbours of site i. Each site has 4 nearest neighbours normally.

		if (nsites == 8) then                  ! betts lattice for 8 sites
			allocate(neighbours(nsites,4))
			neighbours(1,1) = 8; neighbours(1,2) = 7; neighbours(1,3) = 5; neighbours(1,4) = 3
			neighbours(2,1) = 7; neighbours(2,2) = 8; neighbours(2,3) = 3; neighbours(2,4) = 5
			neighbours(3,1) = 1; neighbours(3,2) = 2; neighbours(3,3) = 4; neighbours(3,4) = 6
			neighbours(4,1) = 5; neighbours(4,2) = 3; neighbours(4,3) = 8; neighbours(4,4) = 7
			neighbours(5,1) = 2; neighbours(5,2) = 1; neighbours(5,3) = 6; neighbours(5,4) = 4
			neighbours(6,1) = 3; neighbours(6,2) = 5; neighbours(6,3) = 7; neighbours(6,4) = 8
			neighbours(7,1) = 4; neighbours(7,2) = 6; neighbours(7,3) = 1; neighbours(7,4) = 2
			neighbours(8,1) = 6; neighbours(8,2) = 4; neighbours(8,3) = 2; neighbours(8,4) = 1
		end if

		if (nsites == 4) then                  ! linear 4 site lattice
			allocate(neighbours(nsites,2))
			neighbours(1,1) = 4; neighbours(1,2) = 2
			neighbours(2,1) = 1; neighbours(2,2) = 3
			neighbours(3,1) = 2; neighbours(3,2) = 4
			neighbours(4,1) = 3; neighbours(4,2) = 1
		end if

		if (nsites == 2) then                 ! linear 2 site lattice
			allocate(neighbours(nsites,1))
			neighbours(1,1) = 2; neighbours(2,1) = 1
		end if

	end subroutine make_neighbours

	!-------------------------------------------------------

	subroutine matrix_sizes()

		implicit none

		integer :: n_up,n_dn

		do n_up=0,nsites
			do n_dn=0,nsites
				msize(n_up,n_dn) = choose(nsites,n_up)*choose(nsites,n_dn)
				if (n_dn == 0 .and. n_up == 0) then
					mblock(n_up,n_dn) = 1
				else if (n_dn == 0) then
					mblock(n_up,n_dn) = mblock(n_up-1,nsites) + msize(n_up-1,nsites)
				else 
					mblock(n_up,n_dn) = mblock(n_up,n_dn-1) + msize(n_up,n_dn-1)
				end if
			end do
		end do

	end subroutine matrix_sizes

	!-------------------------------------------------------

	subroutine make_hamiltonian2(t)

		! this program makes the hamiltonians off diagonal terms. On diagonal terms are added during each loop

		implicit none

		real(dp), intent(in) :: t

		integer :: istate,isite, inbr,new_state(2),phase, ne, i, trans_site(2), new_index,j,state_index,y,n_up,n_dn
		"

for ((n_up=0;n_up<=nsites;n_up++)); do
	echo -n "		"
	for ((n_dn=0;n_dn<=nsites;n_dn++)); do
		echo -n "H$n_up$n_dn=0.0_dp"
		if [[ n_dn != $nsites ]]; then
			echo -n "; "
		fi
	done
	echo ""
done

echo "
		call matrix_sizes()

		do n_up = 0,nsites
		do n_dn = 0,nsites
		do istate = mblock(n_up,n_dn),mblock(n_up,n_dn) + msize(n_up,n_dn)-1
			do isite = 1,nsites
				if (ibits(fock_states(1,istate),isite-1,1) == 1) then"
if [ $nsites == 2 ]; then
	echo -n "					do y=1,1"						
fi
if [ $nsites == 3 ] || [ $nsites == 4 ]; then
	echo -n "					do y=1,2"
fi
if [ $nsites == 8 ]; then
	echo -n "					do y=1,4"
fi					
echo "
						new_state(1) = IBCLR(fock_states(1,istate),isite-1)
						inbr = neighbours(isite,y)
						if (ibits(new_state(1),inbr-1,1) == 0) then
							new_state(2) = fock_states(2,istate)
							ne = 0
							trans_site(1) = inbr; trans_site(2) = isite
							do i=MINVAL(trans_site),MAXVAL(trans_site)-1
								ne = ne + ibits(new_state(1),i-1,1)     ! count the number of up electrons in that state
								ne = ne + ibits(new_state(2),i-1,1)     ! count the number of down electrons in that state
							end do
							if (MOD(ne,2) == 0) then 
								phase = 1
							else
								phase = -1
							end if
							new_state(1) = ibset(new_state(1),inbr-1)
							do j=1,total_states
								if(fock_states(1,j) == new_state(1) .and. fock_states(2,j) == new_state(2)) then
								new_index = j
								end if
							end do
							state_index = istate + 1 - mblock(n_up,n_dn)
							new_index = new_index + 1 - mblock(n_up,n_dn)"

echo "							select case (n_up)"
for ((i=0; i<=nsites; i++)); do
	echo "								case($i)"
	echo "									select case (n_dn)"
	for ((j=0; j<=nsites; j++)); do
		echo "										case($j)"
		echo "											H$i$j(state_index,new_index) = t*phase"
	done
	echo "									end select"
done
echo -n "							end select"

echo "
						end if
					end do
				end if
				if (ibits(fock_states(2,istate),isite-1,1) == 1) then"
if [[ $nsites == 2 ]]; then
	echo -n "					do y=1,1"						
fi
if [[ $nsites == 4 ]]; then
	echo -n "					do y=1,2"
fi
if [[ $nsites == 8 ]]; then
	echo -n "					do y=1,4"
fi							
echo "
						new_state(2) = IBCLR(fock_states(2,istate),isite-1)
						inbr = neighbours(isite,y)
						if (ibits(new_state(2),inbr-1,1) == 0) then
							new_state(1) = fock_states(1,istate)
							ne = 0
							trans_site(1) = inbr; trans_site(2) = isite
							do i=MINVAL(trans_site)+1,MAXVAL(trans_site)
								ne = ne + ibits(new_state(1),i-1,1)     ! count the number of up electrons in that state
								ne = ne + ibits(new_state(2),i-1,1)     ! count the number of down electrons in that state
							end do
							if (MOD(ne,2) == 0) then 
								phase = 1
							else
								phase = -1
							end if
							new_state(2) = ibset(new_state(2),inbr-1)
							do j=1,total_states
								if(fock_states(1,j) == new_state(1) .and. fock_states(2,j) == new_state(2)) then
								new_index = j
								end if
							end do
							state_index = istate + 1 - mblock(n_up,n_dn)
							new_index = new_index + 1 - mblock(n_up,n_dn)"

echo "							select case (n_up)"
for ((i=0; i<=nsites; i++)); do
	echo "								case($i)"
	echo "									select case (n_dn)"
	for ((j=0; j<=nsites; j++)); do
		echo "										case($j)"
		echo "											H$i$j(state_index,new_index) = t*phase"
	done
	echo "									end select"
done
echo -n "							end select"

echo "
						end if
					end do
				end if
			end do
		end do
		end do
		end do


	end subroutine make_hamiltonian2

	!-------------------------------------------------------

	subroutine solve_hamiltonian2(E,U,mu)

		! this program makes the on diagonal terms and solves it

		implicit none

		integer :: n_up, n_dn,i,j,ne,isite,istate

		real(dp), intent(in) :: E(nsites)
  		real(dp), intent(in) :: mu 
  		real(dp), intent(in) :: U

		!------for lapack------------
  		integer :: INFO = 0
  		integer :: LWORK
 		real(dp), allocatable, dimension(:) :: WORK
 		real(dp), allocatable, dimension(:) :: wtemp
 		real(dp), allocatable, dimension(:,:) :: htemp

		do n_up=0,nsites
			do n_dn=0,nsites
				
				allocate(htemp(msize(n_up,n_dn),msize(n_up,n_dn)),wtemp(msize(n_up,n_dn)))
				"

echo "				select case (n_up)"
for ((i=0; i<=nsites; i++)); do
	echo "					case($i)"
	echo "						select case (n_dn)"
	for ((j=0; j<=nsites; j++)); do
		echo "							case($j)"
		echo "								htemp=H$i$j"
	done
	echo "						end select"
done
echo "				end select"

echo "
				wtemp=0.0_dp

				do istate=1,msize(n_up,n_dn)
					do isite=1,nsites
						ne=0
						ne = ne + IBITS(fock_states(1,istate+mblock(n_up,n_dn)-1),isite-1,1)
						ne = ne + IBITS(fock_states(2,istate+mblock(n_up,n_dn)-1),isite-1,1)
						htemp(istate,istate) = htemp(istate,istate) + ne*E(isite)
						if (ne == 2) then 
							htemp(istate,istate) = htemp(istate,istate) + U
						end if
					end do
				end do

				LWORK = 3*msize(n_up,n_dn)

			  	allocate(WORK(LWORK))

				call dsyev('v','u',msize(n_up,n_dn),htemp,msize(n_up,n_dn),wtemp,WORK,LWORK,INFO)
				if (INFO /= 0) then
			   		write(*,*) 'Problem with Lapack. Error code:', INFO
			   		stop
				end if 

				deallocate(WORK)

				do i=1,msize(n_up,n_dn)
			   		grand_potential(i+mblock(n_up,n_dn)-1) = wtemp(i) - mu*(n_up+n_dn)  ! grand potentials
				end do

				do i=1,msize(n_up,n_dn)
			   		eigenvectors(i+mblock(n_up,n_dn)-1,mblock(n_up,n_dn):mblock(n_up,n_dn)+msize(n_up,n_dn)) = htemp(1:msize(n_up,n_dn),i)  ! eigenvectors
				end do

				deallocate(htemp,wtemp)
			end do
		end do

	end subroutine solve_hamiltonian2

	!-------------------------------------------------------

	integer function choose(j,k)

	    implicit none
	    
	    integer :: j,k,i2
	    integer (kind=8) :: tj,tk,tchoose

	    tchoose = 1
	    tj = j
	    tk = k
	    do i2 = tj-tk+1,tj
	       tchoose = tchoose * i2
	    end do
	    do i2 = 2, tk
	       tchoose = tchoose / i2
	    end do
	    choose = tchoose

	end function choose

	!------------------------------------------------------

end module"