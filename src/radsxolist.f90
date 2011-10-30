!-----------------------------------------------------------------------
! $Id$
!
! Copyright (C) 2011  Remko Scharroo (Altimetrics LLC)
! See LICENSE.TXT file for copying and redistribution conditions.
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!-----------------------------------------------------------------------

!*radsxolist -- RADS crossover lister
!+
program radsxolist

! This program lists the contents of RADS netCDF crossover files and
! computes statistics.
!-----------------------------------------------------------------------
use rads
use rads_time
use netcdf
use rads_netcdf
integer(fourbyteint) :: ncid, i, k, icol, ios, nvar, nxo, ntrk, id_satid, id_track, id_sla, id_new, id_old
real(eightbytereal), allocatable :: var(:,:,:), stat(:,:,:)
integer(fourbyteint), allocatable :: track(:,:)
logical, allocatable :: mask(:)
type :: trk_
	real(eightbytereal) :: equator_lon, equator_time, start_time, end_time
	integer(twobyteint) :: nr_alt, nr_xover, satid, cycle, pass
end type
type(trk_), allocatable :: trk(:)
character(len=256) :: fmt_string
character(len=80) :: arg, filename
character(len=1) :: mode = ''
character(len=4) :: statname(5) = (/ 'min ', 'max ', 'mean', 'rms ', 'std ' /)
integer(fourbyteint), parameter :: msat = 12
type :: sat_
	character(len=4) :: name
	real(eightbytereal) :: period, altsig, orberr, inclination
end type sat_
type(sat_) :: sat(msat)
integer(fourbyteint), parameter :: maxtrk = 32768
logical :: diff = .false., stat_only = .false.
real(eightbytereal) :: t0 = 0d0, t1 = 0d0, lon0 = 0d0, lon1 = 0d0, lat0 = 0d0, lat1 = 0d0, dt0 = 0d0, dt1 = 0d0

! Initialize RADS or issue help
call synopsis

! Satellite definitions
sat( 1) = sat_ ('g3', 6037.582d0, 0.20d0, 0.800d0,  60.00d0)
sat( 2) = sat_ ('ss', 6037.582d0, 0.07d0, 0.800d0, 108.05d0)
sat( 3) = sat_ ('gs', 6037.582d0, 0.07d0, 0.150d0, 108.05d0)
sat( 4) = sat_ ('e1', 6035.928d0, 0.05d0, 0.050d0,  98.54d0)
sat( 5) = sat_ ('tx', 6745.759d0, 0.02d0, 0.035d0,  66.04d0)
sat( 6) = sat_ ('pn', 6745.759d0, 0.04d0, 0.035d0,  66.04d0)
sat( 7) = sat_ ('e2', 6035.928d0, 0.05d0, 0.050d0,  98.54d0)
sat( 8) = sat_ ('g1', 6037.582d0, 0.05d0, 0.150d0, 108.05d0)
sat( 9) = sat_ ('j1', 6745.759d0, 0.04d0, 0.035d0,  66.04d0)
sat(10) = sat_ ('n1', 6035.928d0, 0.05d0, 0.050d0,  98.54d0)
sat(11) = sat_ ('j2', 6745.759d0, 0.04d0, 0.035d0,  66.04d0)
sat(12) = sat_ ('c2', 5953.579d0, 0.07d0, 0.050d0,  92.50d0)

! Scan command line arguments
do i = 1,iargc()
	call getarg(i,arg)
	k = 1
	if (arg(1:2) == '--') k = 3
	if (arg(k:k+3) == 'lon=') then
		read (arg(k+4:),*) lon0,lon1
	else if (arg(k:k+3) == 'lat=') then
		read (arg(k+4:),*) lat0,lat1
	else if (arg(k:k+2) == 'dt=') then
		read (arg(k+3:),*,iostat=ios) dt0,dt1
		if (dt0 > dt1) then
			dt1 = dt0
			dt0 = 0d0
		endif
		dt0 = dt0 * 86400d0
		dt1 = dt1 * 86400d0
	else if (datearg(arg(k:),t0,t1)) then
	else if (arg == '-d') then
		diff = .true.
	else if (arg(:2) == '-o') then
		mode = arg(3:3)
	else if (arg(:2) == '-s') then
		stat_only = .true.
	endif
enddo

! Now process each file
do i = 1,iargc()
	call getarg(i,filename)
	if (filename(:1) == '-' .or. index(filename, '=') > 0) cycle
	call process
enddo

contains

!***********************************************************************

subroutine process
integer(fourbyteint) :: i, j, k

! Open netCDF file
call nfs (nf90_open (filename, nf90_write, ncid))

! Get the number of xovers and number of tracks
call nfs (nf90_inquire_dimension (ncid, 2, len=nxo))
call nfs (nf90_inquire_dimension (ncid, 3, len=ntrk))
if (ntrk >= maxtrk) then
	write (*,'(a)') 'Output format does not allow track numbers exceeding 32767. We will modulo them.'
endif

600 format ( &
'# File name = ',a/ &
'# Xovers in = ',i9/ &
'# Tracks in = ',i9)
write (*, 600) trim(filename), nxo, ntrk
icol = 0
fmt_string = '('

! Read all the "base variables" into memory
id_track = get_varid('track')
id_satid = get_varid('satid')
nvar = (id_satid - id_track - 1)
allocate (track(2,nxo), trk(ntrk), var(2,nxo,-1:nvar), stat(2,-1:nvar,5), mask(nxo))
mask = .true.
call get_var_1d (get_varid('lat'), var(1,:,-1))
call get_var_1d (get_varid('lon'), var(2,:,-1))
call get_var_2d (get_varid('time'), var(:,:,0))
call nfs (nf90_get_var (ncid, id_track, track))
call nfs (nf90_get_var (ncid, id_satid, trk%satid))
call nfs (nf90_get_var (ncid, get_varid('cycle'), trk%cycle))
call nfs (nf90_get_var (ncid, get_varid('pass'), trk%pass))
call nfs (nf90_get_var (ncid, get_varid('equator_lon'), trk%equator_lon))
call nfs (nf90_get_var (ncid, get_varid('equator_time'), trk%equator_time))
call nfs (nf90_get_var (ncid, get_varid('start_time'), trk%start_time))
call nfs (nf90_get_var (ncid, get_varid('end_time'), trk%end_time))
call nfs (nf90_get_var (ncid, get_varid('nr_xover'), trk%nr_xover))
call nfs (nf90_get_var (ncid, get_varid('nr_alt'), trk%nr_alt))

! Now load all the "data variables"
do i = 1,nvar
	call get_var_2d (id_track + i, var(:,:,i))
enddo
fmt_string(len_trim(fmt_string)-3:) = ')'

! Exchange any correction if requested
do i = 1,iargc()
	call getarg (i,arg)
	if (arg(:2) == '-r') then
		j = index(arg,'=')
		id_old = get_varid(arg(3:j-1)) - id_track
		id_new = get_varid(arg(j+1:)) - id_track
		id_sla = get_varid('sla') - id_track
		if (arg(3:5) == 'alt') then	! Add change to altitude
			var(:,:,id_sla) = var(:,:,id_sla) + (var(:,:,id_new) - var(:,:,id_old))
		else	! Subtract change to corrections
			var(:,:,id_sla) = var(:,:,id_sla) - (var(:,:,id_new) - var(:,:,id_old))
		endif
	endif
enddo

! Sort first and last depending on mode
select case (mode)
case ('A')
	call reorder (mod(trk(track(1,:))%pass,2) < mod(trk(track(2,:))%pass,2))
	write (*,610) 'ascending - descending'
case ('a')
	call reorder (mod(trk(track(2,:))%pass,2) < mod(trk(track(1,:))%pass,2))
	write (*,610) 'descending - ascending'
case ('T')
	call reorder (var(1,:,0) < var(2,:,0))
	write (*,610) 'later - earlier measurement'
case ('t')
	call reorder (var(2,:,0) < var(1,:,0))
	write (*,610) 'earlier - later measurement'
case ('S')
	call reorder (trk(track(1,:))%satid < trk(track(2,:))%satid)
	write (*,610) 'higher - lower satellite ID'
case ('s')
	call reorder (trk(track(2,:))%satid < trk(track(1,:))%satid)
	write (*,610) 'lower - higher satellite ID'
case default
	write (*,610) 'native'
end select
610 format ('# Order     = ',a)

! Now collapse the data if needing difference
if (diff) var(1,:,1:nvar) = var(1,:,1:nvar) - var(2,:,1:nvar)

! Mask out data not in specified range
if (lat1 > lat0) where (var(1,:,-1) < lat0 .or. var(1,:,-1) > lat1) mask = .false.
if (lon1 > lon0) where (var(2,:,-1) < lon0 .or. var(2,:,-1) > lon1) mask = .false.
if (t1   > t0  ) where (var(1,:, 0) < t0   .or. var(1,:, 0) > t1   .or. &
						var(2,:, 0) < t0   .or. var(2,:, 0) > t1  ) mask = .false.
if (dt1 > dt0) where (abs(var(1,:,0)-var(2,:,0)) < dt0 .or. abs(var(1,:,0)-var(2,:,0)) > dt1) mask = .false.

! Print out data
if (stat_only) then
	! Skip
else if (diff) then
	do i = 1,nxo
		if (mask(i)) write (*,fmt_string) var(:,i,-1:0),var(1,i,1:nvar)
	enddo
else
	do i = 1,nxo
		if (mask(i)) write (*,fmt_string) var(:,i,:)
	enddo
endif

! Do statistics
nxo = count(mask)
write (*,615) nxo
615 format ('# Xovers out= ',i9)
do j = -1,nvar
	do k = 1,2
		stat(k,j,1) = minval(var(k,:,j),mask)
		stat(k,j,2) = maxval(var(k,:,j),mask)
		stat(k,j,3) = sum(var(k,:,j),mask) / nxo
		stat(k,j,4) = sqrt(sum(var(k,:,j)**2,mask)/nxo)
		stat(k,j,5) = sqrt(stat(k,j,4)**2 - stat(k,j,3)**2)
	enddo
enddo
do i = 1,5
	write (*,620) statname(i)
	if (diff) then
		write (*,fmt_string) stat(:,-1:0,i),stat(1,1:nvar,i)
	else
		write (*,fmt_string) stat(:,:,i)
	endif
enddo
620 format ('# ',a,' : ',$)

call nfs (nf90_close (ncid))
deallocate (track, trk, var, stat, mask)
end subroutine process

!***********************************************************************

subroutine synopsis
if (rads_version ('$Revision$','RADS crossover file lister')) return
write (0,1300)
1300 format (/ &
'usage: radsxolist [options] filename ...' // &
'Required argument:' / &
'  filename          : Input xover file name (extension .nc)'// &
'Optional arguments [options] are:'/ &
'  lon=lon0,lon1     : specify longitude boundaries (deg)'/ &
'  lat=lat0,lat1     : specify latitude boundaries (deg)'/ &
'  t=t0,t1           : specify time selection'/ &
'                      (optionally use ymd=, doy=, sec= for [YY]YYMMDD[HHMMSS], YYDDD, or SEC85)'/ &
'  dt=[dtmin,]dtmax  : use only xovers with [dtmin <] dt < dtmax (days)'/&
'  -d                : Write out xover differences (default is both values)'/ &
'  -o[A|a|S|s|T|t]   : Order of the xover values (or difference):'/ &
'                      A|a = Ascending-Descending or vv'/ &
'                      S|s = Higher-lower satellite ID or vv'/ &
'                      T|t = Later-earlier measurement or vv'/ &
'  -s                : Print statistics only')
stop
end subroutine synopsis

!***********************************************************************

function get_varid (name)
character(len=*), intent(in) :: name
integer(fourbyteint) :: get_varid
call nfs (nf90_inq_varid(ncid,name,get_varid))
end function get_varid

!***********************************************************************

subroutine get_var_1d (varid, array)
integer(fourbyteint), intent(in) :: varid
real(eightbytereal), intent(out) :: array(:)
real(eightbytereal) :: value
character(len=rads_naml) :: long_name
character(len=rads_varl) :: units, fmt
call nfs (nf90_get_var (ncid, varid, array))
if (nf90_get_att (ncid, varid, 'scale_factor', value) == nf90_noerr) array = array * value
if (nf90_get_att (ncid, varid, 'add_offset', value) == nf90_noerr) array = array + value
if (nf90_get_att (ncid, varid, 'long_name', long_name) /= nf90_noerr) long_name = ''
if (nf90_get_att (ncid, varid, 'units', units) /= nf90_noerr) units = ''
if (nf90_get_att (ncid, varid, 'format', fmt) /= nf90_noerr) fmt = 'f0.3'
fmt_string = trim(fmt_string) // trim(fmt) // ',1x,'
icol = icol + 1
write (*,600) icol,trim(long_name),trim(units)
600 format ('# Col ',i2,'    = ',a,' [',a,']')
end subroutine get_var_1d

!***********************************************************************

subroutine get_var_2d (varid, array)
integer(fourbyteint), intent(in) :: varid
real(eightbytereal), intent(out) :: array(:,:)
real(eightbytereal) :: value
character(len=rads_naml) :: long_name
character(len=rads_varl) :: units, fmt
call nfs (nf90_get_var (ncid, varid, array))
if (nf90_get_att (ncid, varid, 'scale_factor', value) == nf90_noerr) array = array * value
if (nf90_get_att (ncid, varid, 'add_offset', value) == nf90_noerr) array = array + value
if (nf90_get_att (ncid, varid, 'long_name', long_name) /= nf90_noerr) long_name = ''
if (nf90_get_att (ncid, varid, 'units', units) /= nf90_noerr) units = ''
if (nf90_get_att (ncid, varid, 'format', fmt) /= nf90_noerr) fmt = 'f0.3'
if (diff .and. varid /= 3) then
	icol = icol + 1
	fmt_string = trim(fmt_string) // trim(fmt) // ',1x,'
	write (*,600) icol,trim(long_name),trim(units)
else
	icol = icol + 2
	fmt_string = trim(fmt_string) // trim(fmt) // ',1x,' // trim(fmt) // ',1x,'
	write (*,610) icol-1,icol,trim(long_name),trim(units)
endif
600 format ('# Col ',i2,'    = ',a,' [',a,']')
610 format ('# Col ',i2,'-',i2,' = ',a,' [',a,']')
end subroutine get_var_2d

!***********************************************************************

subroutine reorder (order)
logical, intent(in) :: order(:)
integer(fourbyteint) :: i, j
do i = 1,nxo
	if (order(i)) then
		do j = 0,nvar
			call flip(var(:,i,j))
		enddo
	endif
enddo
end subroutine reorder

subroutine flip (a)
real(eightbytereal), intent(inout) :: a(2)
real(eightbytereal) :: b
b = a(1)
a(1) = a(2)
a(2) = b
end subroutine flip

end program radsxolist