module accumulator_routines
    
    use precision_parameters
    
    use setup_data, only: datapath, project, extension, iofill, cfast_input_file_position 
    
    use input_routines, only: exehandle
    use pp_params, only: mxgenerators, mxpntsarray, mxseeds, mxfields, rnd_seeds, restart_values
    use montecarlo_data, only: generatorinfo, n_generators, fieldinfo, n_fields, mc_write_seeds
    use preprocessor_types, only: random_generator_type
    use preprocessor_output_routines, only: flush_parameters_buffer, setup_col_parameters_output, &
        open_preprocessor_outputfiles, initialize_preprocessor_output_routines, &
        add_filename_to_parameters, add_seeds_to_seeds_buffer, flush_seeds_buffer
    use utility_routines, only: readcsvformat
    
    implicit none
    external cfastexit
    
    private

    public accumulator

    contains
    
    !-------------------------accumulator------------------------------------------------
    
    subroutine accumulator 
    
    implicit none

! Variables
    
    integer, parameter :: numr = 2
    integer, parameter :: numc = 3000
    
    integer :: iunit, maxrowio, maxcolio, maxrowcmd, maxcolcmd, nstart, iunit2, maxrowtmp, maxcoltmp
    integer :: nend, maxcolout
    logical :: lend
    
    real(eb), allocatable :: iossx(:, :), tmpx(:, :)
    character, allocatable :: iossc(:, :)*(128), tmpc(:,:)*(128)
    
    integer :: i, j, maxrowend
    character(len=256) :: infile, cmdfile, outfile, tmpext, inpath, outpath
    character(len=512) :: lbuf

    
    allocate(iossx(numr, numc), tmpx(2, numc))
    allocate(iossc(numr, numc), tmpc(2, numc))
    
! Body of GetData
    
    call do_cmd_line(infile, inpath, outfile, outpath)
    lbuf = ' '
    lbuf = trim(inpath) // trim(infile)
    open(newunit = iunit, file = trim(lbuf))
    
    nstart = 1
    nend = 1
    lend = .false.
    i = 1
    call readcsvformat(iunit, iossx, iossc, numr, numc, nstart, 2, maxrowio, maxcolio, lend, iofill)
    if (.not.lend) then
        call fndOpenMCFile(iossc(2,1), inpath, iunit2)
        call readcsvformat(iunit2, tmpx, tmpc, 2, numc, 1, -1, maxrowtmp, maxcoltmp, lend, iofill)
        close(iunit2)
        if (.not.lend) then
            do  j = 2, maxcoltmp
                iossc(1,maxcolio + j - 1) = tmpc(1,j)
                iossx(2,maxcolio + j - 1) = tmpx(2,j)
                write(iossc(2,maxcolio + j - 1),*) iossx(2,maxcolio + j - 1)
            end do 
            maxcolout = maxcolio + maxcoltmp-1
            open(newunit = iunit2, file = outfile)
            call writecsvformat(iunit2, iossx, iossc, numr, numc, 1, 2, maxcolout, iofill)
            close(iunit2)
        else
            write(*,*) 'Number 2 first case does not open'
            call cfastexit('accumulator', 1)
        end if
    else
        write(*,*) 'Number 1 could not read iofile'
        call cfastexit('acumulator', 2)
    end if
        
    
    nstart = nstart + 2
    call readcsvformat(iunit, iossx, iossc, numr, numc, nstart, 1, maxrowio, maxcolio, lend, iofill)
    do while (.not. lend)
        write(*,*)'file = ',trim(iossc(i,1))
        if (.not. lend) then
            call fndOpenMCFile(iossc(i,1), inpath, iunit2)
            call readcsvformat(iunit2, tmpx, tmpc, 2, numc, 1, -1, maxrowtmp, maxcoltmp, lend, iofill)
            close(iunit2)
            do j = 2, maxcoltmp
                iossx(1,maxcolio + j - 1) = tmpx(2,j)
                write(iossc(i,maxcolio + j - 1),*) iossx(i,maxcolio + j - 1)
            end do 
            open(newunit=iunit2,file = outfile, position = 'append')
            call writecsvformat(iunit2, iossx, iossc, numr, numc, 1, 1, maxcolout, iofill)
            close(iunit2)
        end if 
        nstart = nstart + 1
        call readcsvformat(iunit, iossx, iossc, numr, numc, nstart, 1, maxrowio, maxcolio, lend, iofill)
    end do 
    close(iunit)

    end subroutine accumulator
    
    !----------------------------do_cmd_line-------------------------------------------------
    
    subroutine do_cmd_line(infile, inpath, outfile, outpath)
    
    character(len=256), intent(out) :: infile,  outfile, inpath, outpath
    
    character(len=256) :: exepath, ext1, ext2, lbuf
    integer :: narg, iarg, status
    integer(kind=4) :: ilen
    
    narg = command_argument_count()
    cfast_input_file_position = 3
    
    if (narg >= 3) then
        call exehandle(exepath, inpath, infile, ext1)
    end if
    
    iarg = 4
    do while(iarg <= narg)
        call get_command_argument(iarg, lbuf, ilen, status)
        if (ilen>0) then
            if (lbuf(1:1) /= '-') then
                cfast_input_file_position = iarg
                call exehandle(exepath, outpath, outfile, ext2)
                infile = trim(infile) // '.csv'
                outfile = trim(outfile) // '.csv'
                return
            end if
        end if 
        iarg = iarg + 1
    end do
    
    outpath = inpath
    outfile = trim(infile) // '_out.csv'
    infile = trim(infile) // '.csv'
    
    return
    end subroutine do_cmd_line
    
    ! --------------------------- writecsvformat -------------------------------------------

    subroutine writecsvformat (iunit, x, c, numr, numc, nstart, maxrow, maxcol, iofill)

    !     routine: writecsvformat
    !     purpose:writess a comma-delimited file as generated by Micorsoft Excel, assuming that all
    !              the data is in the form of real numbers
    !     arguments: iunit  = logical unit, already open to .csv file
    !                x      = array of dimension (numr,numc) for values in spreadsheet
    !                c      = character array of same dimenaion as x for character values in spreadsheet
    !                numr   = # of rows of arrays x and c
    !                numc   = # of columns of arrays x and c
    !                nstart = starting row of spreadsheet to read
    !                maxrow   = actual number of rows read
    !                maxcol   = actual number of columns read
    !                iofill   = logical unit number for writing error messages (if any)

    implicit none

    integer, parameter :: eb = selected_real_kind(12)


    integer, intent(in) :: iunit, numr, numc, nstart, iofill, maxrow, maxcol

    real(eb), intent(in) :: x(numr,numc)
    character, intent(inout) :: c(numr,numc)*(*)

    character :: buf*204800, token*128
    integer :: i, j, nrcurrent, ic, icomma, ios, nc, ie
    real(eb) :: tmp
    
    do i = nstart, maxrow
        buf = '                    '
        ic = 1
        do j = 1, maxcol
            if (x(i,j) /= 0.0) then
                write(c(i,j),'(e16.9)') x(i,j)
            end if
            ie = ic + len_trim(c(i,j))
            buf(ic:ie) = trim(c(i,j))
            ic = ie+1
            buf(ic:ic) = ','
            ic = ic+1
        end do
        write(iunit,'(A)') buf(1:ic)
    end do
    
    return
    end subroutine writecsvformat
    
    !-------------------clr_arrays(x, c, numr, numc)
    
    subroutine clr_arrays(x, c, numr, numc)

    implicit none
    
    integer, parameter :: eb = selected_real_kind(12)

    integer, intent(in) :: numr, numc
    real(eb), intent(out) :: x(numr, numc)
    character, intent(out) :: c(numr, numc)*(*)

    integer :: i, j
    
    do i = 1, numr
        do j = 1, numc
            x(i,j) = 0.0_eb
            c(i,j) = ' '
        end do
    end do
    return
    end subroutine clr_arrays
    
    !---------------------------------------fndOpenMCFile(filename, path, iunit)---------------------------------------------------------------------------------------------
    
    subroutine fndOpenMCFile(filename, path, iunit)
    
    implicit none

    integer, parameter :: eb = selected_real_kind(12)
    
    character, intent(in) :: filename*(*), path*(*)
    integer, intent(out) :: iunit
    
    character :: fn*(128)
    integer :: i, j, lc, fc
    
    fn = trim(filename)
    lc = len_trim(fn)
    do i = lc-1, 1, -1
        if (fn(i:i)=='/'.or.fn(i:i)=='\') then
            fc = i + 1
            exit
        end if
    end do
    
    fn = trim(path) // fn(fc:lc) // '_mc.csv'
    open(newunit = iunit,file = fn)
    
    return
    end subroutine fndOpenMCFile
    
end module accumulator_routines