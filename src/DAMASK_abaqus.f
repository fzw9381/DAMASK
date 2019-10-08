!--------------------------------------------------------------------------------------------------
!> @author Philip Eisenlohr, Max-Planck-Institut für Eisenforschung GmbH
!> @author Franz Roters, Max-Planck-Institut für Eisenforschung GmbH
!> @author Koen Janssens, Paul Scherrer Institut
!> @author Arun Prakash, Fraunhofer IWM
!> @author Martin Diehl, Max-Planck-Institut für Eisenforschung GmbH
!> @brief interfaces DAMASK with Abaqus/Standard
!> @details put the included file abaqus_v6.env in either your home or model directory, 
!> it is a minimum Abaqus environment file  containing all changes necessary to use the 
!> DAMASK subroutine (see Abaqus documentation for more information on the use of abaqus_v6.env)
!> @details  Abaqus subroutines used:
!> @details   - UMAT
!> @details   - DFLUX
!--------------------------------------------------------------------------------------------------
#define Abaqus

#include "prec.f90"

module DAMASK_interface

 implicit none
 private
 character(len=4), dimension(2),  parameter, public :: INPUTFILEEXTENSION = ['.pes','.inp']
 character(len=4),                parameter, public :: LOGFILEEXTENSION   =  '.log'
 
 public :: &
  DAMASK_interface_init, &
  getSolverJobName

contains

!--------------------------------------------------------------------------------------------------
!> @brief reports and sets working directory
!--------------------------------------------------------------------------------------------------
subroutine DAMASK_interface_init
#if __INTEL_COMPILER >= 1800
 use, intrinsic :: iso_fortran_env, only: &
   compiler_version, &
   compiler_options
#endif
 use ifport, only: &
   CHDIR
 
 implicit none
 integer, dimension(8) :: &
   dateAndTime
 integer :: lenOutDir,ierr
 character(len=256) :: wd

 write(6,'(/,a)') ' <<<+-  DAMASK_abaqus init -+>>>'

 write(6,'(/,a)') ' Roters et al., Computational Materials Science 158:420–478, 2019'
 write(6,'(a)')   ' https://doi.org/10.1016/j.commatsci.2018.04.030'

 write(6,'(/,a)') ' Version: '//DAMASKVERSION

! https://github.com/jeffhammond/HPCInfo/blob/master/docs/Preprocessor-Macros.md
#if __INTEL_COMPILER >= 1800
 write(6,'(/,a)') ' Compiled with: '//compiler_version()
 write(6,'(a)')   ' Compiler options: '//compiler_options()
#else
 write(6,'(/,a,i4.4,a,i8.8)') ' Compiled with Intel fortran version :', __INTEL_COMPILER,&
                                                      ', build date :', __INTEL_COMPILER_BUILD_DATE
#endif

 write(6,'(/,a)') ' Compiled on: '//__DATE__//' at '//__TIME__

 call date_and_time(values = dateAndTime)
 write(6,'(/,a,2(i2.2,a),i4.4)') ' Date: ',dateAndTime(3),'/',dateAndTime(2),'/', dateAndTime(1)
 write(6,'(a,2(i2.2,a),i2.2)')   ' Time: ',dateAndTime(5),':', dateAndTime(6),':', dateAndTime(7)

 call getoutdir(wd, lenOutDir)
 ierr = CHDIR(wd)
 if (ierr /= 0) then
   write(6,'(a20,a,a16)') ' working directory "',trim(wd),'" does not exist'
   call quit(1)
 endif

end subroutine DAMASK_interface_init


!--------------------------------------------------------------------------------------------------
!> @brief using Abaqus/Standard function to get solver job name
!--------------------------------------------------------------------------------------------------
character(1024) function getSolverJobName()
 
 implicit none
 integer :: lenJobName

 getSolverJobName=''
 call getJobName(getSolverJobName, lenJobName)

end function getSolverJobName


end module DAMASK_interface




#include "commercialFEM_fileList.f90"
 
!--------------------------------------------------------------------------------------------------
!> @brief This is the Abaqus std user subroutine for defining material behavior
!--------------------------------------------------------------------------------------------------
subroutine UMAT(STRESS,STATEV,DDSDDE,SSE,SPD,SCD,&
                RPL,DDSDDT,DRPLDE,DRPLDT,STRAN,DSTRAN,&
                TIME,DTIME,TEMP,DTEMP,PREDEF,DPRED,CMNAME,NDI,NSHR,NTENS,&
                NSTATV,PROPS,NPROPS,COORDS,DROT,PNEWDT,CELENT,&
                DFGRD0,DFGRD1,NOEL,NPT,KSLAY,KSPT,KSTEP,KINC)
 use prec, only: &
   pReal, &
   pInt
 use numerics, only: &
!$ DAMASK_NumThreadsInt, &
   usePingPong
 use FEsolving, only: &
   calcMode, &
   terminallyIll, &
   symmetricSolver
 use debug, only: &
   debug_info, &
   debug_reset, &
   debug_levelBasic, &
   debug_level, &
   debug_abaqus
 use mesh, only:  &
   mesh_unitlength, &
   mesh_FEasCP, &
   mesh_ipCoordinates
 use CPFEM, only: &
   CPFEM_general, &
   CPFEM_init_done, &
   CPFEM_initAll, &
   CPFEM_CALCRESULTS, &
   CPFEM_AGERESULTS, &
   CPFEM_COLLECT, &
   CPFEM_BACKUPJACOBIAN, &
   cycleCounter, &
   theInc, &
   theTime, &
   theDelta, &
   lastIncConverged, &
   outdatedByNewInc, &
   outdatedFFN1, &
   lastStep
 use homogenization, only: &
   materialpoint_sizeResults, &
   materialpoint_results

 implicit none
 integer(pInt),                       intent(in) :: &
   nDi, &                                                                                           !< Number of direct stress components at this point
   nShr, &                                                                                          !< Number of engineering shear stress components at this point
   nTens, &                                                                                         !< Size of the stress or strain component array (NDI + NSHR)
   nStatV, &                                                                                        !< Number of solution-dependent state variables
   nProps, &                                                                                        !< User-defined number of material constants
   noEl, &                                                                                          !< element number
   nPt,&                                                                                            !< integration point number
   kSlay, &                                                                                         !< layer number (shell elements etc.)
   kSpt, &                                                                                          !< section point within the current layer
   kStep, &                                                                                         !< step number
   kInc                                                                                             !< increment number
 character(len=80),                   intent(in) :: &
   cmname                                                                                           !< uses-specified material name, left justified
 real(pReal),                         intent(in) :: &
   DTIME, &
   TEMP, &
   DTEMP, &
   CELENT
 real(pReal), dimension(1),           intent(in) :: & 
   PREDEF, & 
   DPRED
 real(pReal), dimension(2),           intent(in) :: &
   TIME                                                                                             !< step time/total time at beginning of the current increment
 real(pReal), dimension(3),           intent(in) :: &
   COORDS
 real(pReal), dimension(nTens),       intent(in) :: &
   STRAN, &                                                                                         !< total strains at beginning of the increment
   DSTRAN                                                                                           !< strain increments
 real(pReal), dimension(nProps),      intent(in) :: &
   PROPS
 real(pReal), dimension(3,3),         intent(in) :: &
   DROT, &                                                                                          !< rotation increment matrix
   DFGRD0, &                                                                                        !< F at beginning of increment
   DFGRD1                                                                                           !< F at end of increment
 real(pReal),                         intent(inout) :: &                                                             
   PNEWDT, &                                                                                        !< ratio of suggested new time increment
   SSE, &                                                                                           !< specific elastic strain engergy
   SPD, &                                                                                           !< specific plastic dissipation
   SCD, &                                                                                           !< specific creep dissipation
   RPL, &                                                                                           !< volumetric heat generation per unit time at the end of the increment 
   DRPLDT                                                                                           !< varation of RPL with respect to the temperature
 real(pReal), dimension(nTens),       intent(inout) :: &
   STRESS                                                                                           !< stress tensor at the beginning of the increment, needs to be updated
 real(pReal), dimension(nStatV),      intent(inout) :: &
   STATEV                                                                                           !< solution-dependent state variables
 real(pReal), dimension(nTens),       intent(out) :: &
   DDSDDT, &
   DRPLDE
 real(pReal), dimension(nTens,nTens), intent(out) :: &
   DDSDDE                                                                                           !< Jacobian matrix of the constitutive model

 real(pReal) :: temperature                                                                         ! temp by Abaqus is intent(in)
 real(pReal), dimension(6) ::   stress_h
 real(pReal), dimension(6,6) :: ddsdde_h
 integer(pInt) :: computationMode, i, cp_en
 logical :: cutBack
 
#ifdef _OPENMP
 integer :: defaultNumThreadsInt                                                                    !< default value set by Abaqus
 include "omp_lib.h"
 defaultNumThreadsInt = omp_get_num_threads()                                                       ! remember number of threads set by Marc
 call omp_set_num_threads(DAMASK_NumThreadsInt)                                                     ! set number of threads for parallel execution set by DAMASK_NUM_THREADS
#endif

 temperature = temp                                                                                 ! temp is intent(in)
 DDSDDT = 0.0_pReal
 DRPLDE = 0.0_pReal

 if (iand(debug_level(debug_abaqus),debug_levelBasic) /= 0 .and. noel == 1 .and. npt == 1) then
   write(6,*) 'el',noel,'ip',npt
   write(6,*) 'got kInc as',kInc
   write(6,*) 'got dStran',dStran
   flush(6)
 endif

 if (.not. CPFEM_init_done) call CPFEM_initAll(noel,npt)

 computationMode = 0
 cp_en = mesh_FEasCP('elem',noel)
 if (time(2) > theTime .or. kInc /= theInc) then                                                    ! reached convergence
   terminallyIll = .false.
   cycleCounter = -1                                                                                ! first calc step increments this to cycle = 0
   if (kInc == 1) then                                                                              ! >> start of analysis << 
     lastIncConverged = .false.                                                                     ! no Jacobian backup
     outdatedByNewInc = .false.                                                                     ! no aging of state
     calcMode = .false.                                                                             ! pretend last step was collection
     write (6,'(i8,1x,i2,1x,a)') noel,npt,'<< UMAT >> start of analysis..!';flush(6)
   else if (kInc - theInc > 1) then                                                                 ! >> restart of broken analysis <<
     lastIncConverged = .false.                                                                     ! no Jacobian backup
     outdatedByNewInc = .false.                                                                     ! no aging of state
     calcMode = .true.                                                                              ! pretend last step was calculation
     write (6,'(i8,1x,i2,1x,a)') noel,npt,'<< UMAT >> restart of analysis..!';flush(6)
   else                                                                                             ! >> just the next inc << 
     lastIncConverged = .true.                                                                      ! request Jacobian backup
     outdatedByNewInc = .true.                                                                      ! request aging of state
     calcMode = .true.                                                                              ! assure last step was calculation
     write (6,'(i8,1x,i2,1x,a)') noel,npt,'<< UMAT >> new increment..!';flush(6)
   endif
 else if ( dtime < theDelta ) then                                                                  ! >> cutBack <<
   lastIncConverged = .false.                                                                       ! no Jacobian backup
   outdatedByNewInc = .false.                                                                       ! no aging of state
   terminallyIll = .false.
   cycleCounter = -1                                                                                ! first calc step increments this to cycle = 0
   calcMode = .true.                                                                                ! pretend last step was calculation
   write(6,'(i8,1x,i2,1x,a)') noel,npt,'<< UMAT >> cutback detected..!';flush(6)
 endif                                                                                              ! convergence treatment end


 if (usePingPong) then
   calcMode(npt,cp_en) = .not. calcMode(npt,cp_en)                                                  ! ping pong (calc <--> collect)
   if (calcMode(npt,cp_en)) then                                                                    ! now --- CALC ---                  
     computationMode = CPFEM_CALCRESULTS
     if ( lastStep /= kStep ) then                                                                  ! first after ping pong
       call debug_reset()                                                                           ! resets debugging
       outdatedFFN1 = .false.
       cycleCounter = cycleCounter + 1_pInt
     endif
     if(outdatedByNewInc) then
       computationMode = ior(computationMode,CPFEM_AGERESULTS)                                      ! calc and age results
       outdatedByNewInc = .false.                                                                   ! reset flag
     endif
   else                                                                                             ! now --- COLLECT ---
     computationMode = CPFEM_COLLECT                                                                ! plain collect
     if(lastStep /= kStep .and. .not. terminallyIll) &
       call debug_info()                                                                            ! first after ping pong reports (meaningful) debugging
     if (lastIncConverged) then
       computationMode = ior(computationMode,CPFEM_BACKUPJACOBIAN)                                  !  collect and backup Jacobian after convergence
       lastIncConverged = .false.                                                                   ! reset flag
     endif
     mesh_ipCoordinates(1:3,npt,cp_en) = mesh_unitlength * COORDS
   endif
 else                                                                                               ! --- PLAIN MODE ---
   computationMode = CPFEM_CALCRESULTS                                                              ! always calc
   if (lastStep /= kStep) then
     if (.not. terminallyIll) &
       call debug_info()                                                                            ! first reports (meaningful) debugging
     call debug_reset()                                                                             ! and resets debugging
     outdatedFFN1  = .false.
     cycleCounter  = cycleCounter + 1_pInt
   endif
   if (outdatedByNewInc) then
     computationMode = ior(computationMode,CPFEM_AGERESULTS)
     outdatedByNewInc = .false.                                                                     ! reset flag
   endif
   if (lastIncConverged) then
     computationMode = ior(computationMode,CPFEM_BACKUPJACOBIAN)                                    ! backup Jacobian after convergence
     lastIncConverged = .false.                                                                     ! reset flag
   endif
 endif
   
   
 theTime  = time(2)                                                                                 ! record current starting time
 theDelta = dtime                                                                                   ! record current time increment
 theInc   = kInc                                                                                    ! record current increment number
 lastStep = kStep                                                                                   ! record step number

 if (iand(debug_level(debug_abaqus),debug_levelBasic) /= 0) then
   write(6,'(a16,1x,i2,1x,a,i8,a,i8,1x,i5,a)') 'computationMode',computationMode,'(',cp_en,':',noel,npt,')'
   flush(6)
 endif
   
 call CPFEM_general(computationMode,usePingPong,dfgrd0,dfgrd1,temperature,dtime,noel,npt,stress_h,ddsdde_h)

!     DAMASK:            11, 22, 33, 12, 23, 13
!     ABAQUS explicit:   11, 22, 33, 12, 23, 13
!     ABAQUS implicit:   11, 22, 33, 12, 13, 23
!     ABAQUS implicit:   11, 22, 33, 12

 ddsdde = ddsdde_h(1:ntens,1:ntens)
 stress = stress_h(1:ntens)
 if(symmetricSolver) ddsdde = 0.5_pReal*(ddsdde + transpose(ddsdde))
 if(ntens == 6) then
   stress_h = stress
   stress(5) = stress_h(6)
   stress(6) = stress_h(5)
   ddsdde_h = ddsdde
   ddsdde(:,5) = ddsdde_h(:,6)
   ddsdde(:,6) = ddsdde_h(:,5)
   ddsdde_h = ddsdde
   ddsdde(5,:) = ddsdde_h(6,:)
   ddsdde(6,:) = ddsdde_h(5,:)
 end if

 statev = materialpoint_results(1:min(nstatv,materialpoint_sizeResults),npt,mesh_FEasCP('elem', noel))

 if (terminallyIll) pnewdt = 0.5_pReal                                                              ! force cutback directly ?
!$ call omp_set_num_threads(defaultNumThreadsInt)                                                   ! reset number of threads to stored default value

end subroutine UMAT

!--------------------------------------------------------------------------------------------------
!> @brief calculate internal heat generated due to inelastic energy dissipation
!--------------------------------------------------------------------------------------------------
SUBROUTINE DFLUX(FLUX,SOL,KSTEP,KINC,TIME,NOEL,NPT,COORDS,&
           JLTYP,TEMP,PRESS,SNAME)
 use prec, only: &
   pReal, &
   pInt
 use thermal_conduction, only: &
   thermal_conduction_getSourceAndItsTangent
 use mesh, only: &
   mesh_FEasCP

 implicit none
 character(len=1024) :: sname
 real(pReal), dimension(2), intent(out) :: flux
 real(pReal), intent(in) :: sol
 Integer(pInt), intent(in) :: Kstep, Kinc, Noel, Npt
 real(pReal), dimension(3), intent(in) :: coords
 real(pReal), intent(in) :: time
 real(pReal) :: Jltyp
 real(pReal), intent(in) :: temp
 real(pReal), intent(in) :: Press

 jltyp = 1
 call thermal_conduction_getSourceAndItsTangent(flux(1), flux(2), sol, npt,mesh_FEasCP('elem',noel))
end subroutine DFLUX

!--------------------------------------------------------------------------------------------------
!> @brief calls the exit function of Abaqus/Standard
!--------------------------------------------------------------------------------------------------
subroutine quit(DAMASK_error)
 use prec, only: &
   pInt
 
 implicit none
 integer(pInt) :: DAMASK_error

 flush(6)
 call xit

end subroutine quit
