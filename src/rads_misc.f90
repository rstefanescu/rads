!-----------------------------------------------------------------------
! $Id$
!
! Copyright (c) 2011-2013  Remko Scharroo (Altimetrics LLC)
! See LICENSE.TXT file for copying and redistribution conditions.
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU Lesser General Public License as
! published by the Free Software Foundation, either version 3 of the
! License, or (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!-----------------------------------------------------------------------

module rads_misc
use typesizes

! These are used by getopt
integer, save :: getopt_ind = 1, getopt_chr = 2
logical, save :: getopt_err = .true.
character(len=160), private, save :: getopt_arg
logical, private, save :: getopt_new = .true.

! Provide a NaN parameter
real(eightbytereal), parameter :: nan = transfer ((/not(0_fourbyteint),not(0_fourbyteint)/),0d0)
logical, parameter :: little_endian = btest(1,0), big_endian = .not.little_endian

!***********************************************************************
!*d_int -- Convert integer to double while accounting for NaNs
!+
! elemental function d_int (i)
! integer(onebyteint) <or> integer(twobyteint) <or> integer(fourbyteint) :: i
! real(eightbytereal) :: d_int
!
! Convert an integer (or integer array) to a double, while taking into
! account that the maximum value for that type of integer (127, 32767, etc)
! indicates NaN.
!
! Arguments:
!  i     : Integer to convert to double
!  d_int : Result as a double real
!-----------------------------------------------------------------------
private :: d_int1, d_int2, d_int4
interface d_int
	module procedure d_int1
	module procedure d_int2
	module procedure d_int4
end interface d_int

!***********************************************************************
!*real_val -- Read array of values from string with optional substitution
!+
! pure subroutine read_val (string, val, translate)
! character(len=*), intent(in) :: string
! integer(fourbyteint) <or> real(eightbytereal), intent(out) :: val(:)
! character(len=*), intent(in), optional :: translate
!
! This routine reads 4-byte integer or 8-byte real values from a string
! <string> into an array <val>. To simplify things when the separators
! between values are not space, comma or tab, we can optionally translate
! all characters in the string <translate> to commas first.
!
! The values in <val> will retain their value when <string> prematurely
! runs out of values.
!
! Arguments:
!  string    : input character string
!  val       : output array of values (integer or double)
!  translate : optional: string of characters that need to be changed
!             to spaces first
!-----------------------------------------------------------------------
private :: read_val_int, read_val_dble
interface read_val
	module procedure read_val_int
	module procedure read_val_dble
end interface read_val

contains

!***********************************************************************
!*getopt -- Get option from command line argument
!
subroutine getopt (optlist, optopt, optarg, unit)
character(len=*), intent(in) :: optlist
character(len=*), intent(out) :: optopt, optarg
integer, intent(in), optional :: unit
!
! This subroutine mimics both the GNU C <getopt> and <getopt_long> functions,
! and provides several enhancements over those functions (see below).
!
! At every call, <getopt> reads a new option and (if required) its
! option argument. By default, <getopt> reads from the command line,
! but if <unit> is specified, it will read from a file containing options
! that is associated with the i/o unit <unit>.
!
! The argument <optlist> may contain both short options (i.e. '-f') or long
! options (i.e. '--file'), in the following way.
! 1) Start with a string of single character short options
! 2) Append, each separated by a space the long options
! 3) Append ':' when an option requires an argument, or '::' when the
!    argument is optional
!
! Example:
! optlist = 'f:qo:v? quiet verbose file: output:: outcome t help'
!
! Note 1: There needs to be no association between short and long options
!    This is different from <getopt_long> and actually more practical in
!    Fortran, because we can easily parse long and short options later with
!    case ('v', 'verbose')
! Note 2: Long options are not required, simply leave them out if not needed.
! Note 3: Short options are not required, leave them out if not needed, but
!    then still start <optlist> with a space before the first long option.
!
! The argument <optopt> returns the short or the (full) long option. This
! routine will match any shorter unique version of the long option but still
! return the full one. If a long option has only one character (though
! discouraged), <optopt> returns the character followed by a ':' to avoid
! confusing it with a short option.
! At the same time, <optarg> will provide the argument to the option.
!
! The routine <getopt> deals in the following manner with errors:
! * An option with a required argument was found, but there was no
!   required argument, because of reaching the end of the input or
!   because the option was followed by another option.
!   <optopt> returns the option, <optarg> returns ''.
! * An argument starts with '--' and no match with an option is found.
!   <optopt> returns ':' and <optarg> the full argument.
! * An argument starts with '-' and no match with an option is found.
!   <optopt> returns ':' and <optarg> the full argument.
! * No match was found. <optopt> returns '' and <optarg> the full argument.
! * End of input is reached. <optopt> returns '!' and <optarg> ''.
!
! Examples of input, <optopt> and <optarg> using <optlist> above:
! -i           optopt = ':', optarg = '-i' (Unknown option)
! -q           optopt = 'q', optarg = '' (Short option)
! --quiet      optopt = 'quiet', optarg = '' (Long option)
! --quiet=0    optopt = 'quiet', optarg = '' (Addition =0 is ignored)
! --q          optopt = 'quiet', optarg = '' (Returning first match)
! --t          optopt = 't:', optarg = '' (Colon added to distinguish from -t)
! -fFILE       optopt = 'f', optarg = 'FILE' (Space is not necessary)
! -f FILE      optopt = 'f', optarg = 'FILE' (Two arguments joined)
! --file FILE  optopt = 'file', optarg = 'FILE' (Separate by space ...)
! --file=FILE  optopt = 'file', optarg = 'FILE' (... or by equal sign)
! --output -q  optopt = 'output', optarg = '' (Optional argument)
! file.txt     optopt = ' ', optarg = 'file.txt' (No match)
!
! Arguments:
!  optlist  : list of short and long options
!  optopt   : option part of the option, without -- or -
!  optarg   : argument of the option
!  unit     : (Optional) input unit number, otherwise command line
!-----------------------------------------------------------------------
integer :: input, i, j, k, n, l
logical :: optional_arg

! Select input unit
if (.not.present(unit)) then
	input = 0
else
	input = unit
endif

! Read next argument when needed
if (.not.getopt_new) then
else if (nextarg()) then
	optopt = '!'
	return ! Return on error
endif

! Arguments '-' and '--' by itself should be regarded as normal arguments
if (getopt_arg(1:2) == '- ' .or. getopt_arg(1:3) == '-- ') then
	optopt = ' '
	optarg = getopt_arg
	return
endif

! Default is no option argument
optarg = ''

l = len(optlist)

! Handle double-dash options
if (getopt_arg(1:2) == '--') then
	getopt_new = .true.
	! Find end of option or first : or =
	i = len_trim(getopt_arg)
	j = scan (getopt_arg, ' :=')
	if (j > 3) i = j - 1
	n = index(optlist, ' ' // getopt_arg(3:i)) ! Scan for space + option without the double-dash
	if (n == 0) then ! Not a recognised option
		optopt = ':'
		optarg = getopt_arg(:i)
		return
	endif
	n = n + 1
	k = scan(optlist(n:), ' :')
	if (k == 0) then
		optopt = optlist(n:)
		if (optopt(2:2) == ' ') optopt(2:2) = ':' ! Distinguish 1-letter option by adding ':'
		return ! No argument to this option
	endif
	k = k + n - 2
	optopt = optlist(n:k)
	if (optopt(2:2) == ' ') optopt(2:2) = ':' ! Distinguish 1-letter option by adding ':'
	if (optlist(k+1:k+1) /= ':') return ! No argument to this option
	if (j > 3) then ! Return the remainder of this argument
		optarg = adjustl(getopt_arg(j+1:))
		return
	endif
	optional_arg = (k+2 <= l .and. optlist(k+2:k+2) == ':')
	if (nextarg()) then
		if (optional_arg) return ! Argument was optional
		if (getopt_err) print '(a,a,a)', &
			'Warning: option "',trim(getopt_arg),'" should contain argument, but end reached'
	else if (getopt_arg(1:1) == '-' .and. getopt_arg(2:2) /= ' ') then
		getopt_new = .false.
		if (optional_arg) return ! Argument was optional
		if (getopt_err) print '(a,a,a)', &
			'Warning: option "',trim(getopt_arg),'" should contain argument, but new option reached'
	else
		optarg = getopt_arg
	endif
	return
endif

! Handle single-dash options
if (getopt_arg(1:1) == '-') then
	getopt_new = .false.
	optopt = getopt_arg(getopt_chr:getopt_chr)
	getopt_chr = getopt_chr + 1
	if (getopt_arg(getopt_chr:) == '') getopt_new = .true.
	n = scan (optlist, optopt(1:1)//' ') ! Scan for the actual option or a space
	if (n == 0 .or. optlist(n:n) == ' ') then ! Not a recognised option
		optarg = '-'//optopt(1:1)
		optopt = ':'
		return
	endif
	if (n == l .or. optlist(n+1:n+1) /= ':') return ! No argument to this option
	if (.not.getopt_new) then
		optarg = adjustl(getopt_arg(getopt_chr:))
		getopt_new = .true.
		return
	endif
	optional_arg = (n+2 <= l .and. optlist(n+2:n+2) == ':')
	if (nextarg()) then
		if (optional_arg) return ! Argument was optional
		if (getopt_err) print '(a,a,a)', &
			'Warning: option "-',trim(optopt),'" should contain argument, but end reached'
	else if (getopt_arg(1:1) == '-' .and. getopt_arg(2:2) /= ' ') then
		getopt_new = .false.
		if (optional_arg) return ! Argument was optional
		if (getopt_err) print '(a,a,a)', &
			'Warning: option "-',trim(optopt),'" should contain argument, but new option reached'
	else
		optarg = getopt_arg
		getopt_new = .true.
	endif
	return
endif

! For compatibility, handle options like lat=0,180
j = index(getopt_arg, '=')
if (j > 1) then
	getopt_new = .true.
	j = scan (getopt_arg, ':=') - 1
	n = index (optlist, ' ' // getopt_arg(:j))
	if (n > 0) then
		n = n + 1
		k = scan (optlist(n:), ' :') + n - 2
		optopt = optlist(n:k)
		optarg = getopt_arg(j+2:)
		return
	endif
endif

! Return simple argument
getopt_new = .true.
optopt = ' '
optarg = getopt_arg
return

contains

! Get the next argument from command line or file
! Return .true. on error
logical function nextarg ()
integer :: ios
if (input > 0) then
	read (input, '(a)', iostat=ios) getopt_arg
	nextarg = (ios /= 0)
else if (getopt_ind > iargc()) then
	nextarg = .true.
else
	call getarg (getopt_ind, getopt_arg)
	getopt_ind = getopt_ind + 1
	nextarg = .false.
endif
getopt_chr = 2
end function nextarg

end subroutine getopt

!***********************************************************************
!*getopt_reset -- Reset to beginning of command line options
!+
subroutine getopt_reset (unit)
integer, intent(in), optional :: unit
!
! By calling this routine the pointer for <getopt> is reset to the
! beginning of the argument list, or the file on input <unit> is rewound
! to the beginning.
!
! Argument:
!   unit  : (Optional) unit of the input file, command line otherwise
!-----------------------------------------------------------------------
if (present(unit)) then
	rewind (unit)
else
	getopt_ind = 1
endif
getopt_chr = 2
getopt_new = .true.
end subroutine getopt_reset

!***********************************************************************
!*strtolower -- Convert string to lower case
!+
elemental function strtolower (string) result (lower)
character(len=*), intent(in) :: string
character(len=len(string)) :: lower
!
! Convert character string to all lower case letters, leaving all non-
! alphabetical characters as is.
!
! Arguments:
!  string : String to be converted
!  lower  : String returned in lower case
!-----------------------------------------------------------------------
integer :: i
do i = 1,len(string)
	if (string(i:i) >= 'A' .and. string(i:i) <= 'Z') then
		lower(i:i) = achar(iachar(string(i:i)) + 32)
	else
		lower(i:i) = string(i:i)
	endif
enddo
end function strtolower

!***********************************************************************
!*strtoupper -- Convert string to upper case
!+
elemental function strtoupper (string) result (upper)
character(len=*), intent(in) :: string
character(len=len(string)) :: upper
!
! Convert character string to all upper case letters, leaving all non-
! alphabetical characters as is.
!
! Arguments:
!  string : String to be converted
!  upper  : String returned in upper case
!-----------------------------------------------------------------------
integer :: i
do i = 1,len(string)
	if (string(i:i) >= 'a' .and. string(i:i) <= 'z') then
		upper(i:i) = achar(iachar(string(i:i)) - 32)
	else
		upper(i:i) = string(i:i)
	endif
enddo
end function strtoupper

!***********************************************************************
!*getlun -- Get free logical unit number
!+
function getlun ()
integer :: getlun
!
! This function returns a logical unit number that is not currently
! connected to any file. A value of 0 is returned if no free unit is found.
!
! Example:
! integer :: unit, getlun
! unit = getlun()
! open (unit=unit, file='filename', status='old')
!-----------------------------------------------------------------------
integer :: unit
logical :: opened

do unit = 99,7,-1
	inquire (unit=unit,opened=opened)
	if (.not.opened) then
		getlun = unit
		return
	endif
enddo
getlun = 0
end function getlun

!***********************************************************************
!*checkenv -- Get environment variable, if it exists
!+
subroutine checkenv (env, string)
character(len=*), intent(in) :: env
character(len=*), intent(inout) :: string
!
! This routine returns the contents of environment variable <env> in the
! variable <string>.
! If the environment variable <env> is not set, <string> is unchanged.
!
! Arguments:
!   env    : Name of the environment variable.
!   string : Upon input: default value for string.
!          : Upon output: contents of the environment variable or default.
!-----------------------------------------------------------------------
character(len=160) :: temp
call getenv (env,temp)
if (temp /= ' ') string = temp
end subroutine checkenv

!***********************************************************************
!*parseenv -- Parse a string for embedded environment variable
!+
recursive subroutine parseenv (input, output)
character(len=*), intent(in) :: input
character(len=*), intent(inout) :: output
!
! This routine parse the string <input> for embedded environment
! variables and replaces them with its value. The result is returned
! in <output>.
! Environment variables are of the form ${parameter}.
! Alternatively use ${parameter:-word} to substitude the expansion of
! word when parameter is unset or empty; or use ${parameter:+word}
! to substitute the expansion of word when parameter is not empty
! (same meaning as in the bash shell).
! Nesting of variable names is not allowed.
!
! Arguments:
!   input  : String to be parsed.
!   output : String with environment variables replaced.
!-----------------------------------------------------------------------
character(len=160) :: env
integer :: j, k = 0, l, m, n
output = input
do
	l = len_trim(output)
	j = index (output(1:), '${')
	if (j == 0) exit
	j = j + 2
	n = 1
	do k = j,l
		if (output(k:k) == '}') then
			n = n - 1
			if (n == 0) exit
		else if (output(k:k) == '{') then
			n = n + 1
		endif
	enddo
	if (n > 0) exit
	k = k - 1
	m = index(output(j:k), ':')
	if (m == 0) then
		call getenv (output(j:k),env)
	else
		m = j + m - 1
		call getenv (output(j:m-1),env)
		if (index ('-=?', output(m+1:m+1)) > 0) then
			if (env == '') env = output(m+2:k)
		else if (output(m+1:m+1) == '+') then
			if (env /= '') env = output(m+2:k)
		endif
	endif
	output = output(:j-3) // trim(env) // output(k+2:)
enddo
end subroutine parseenv

!***********************************************************************
!*outofrange - Verify if value is within limits
!+
function outofrange (limits, value)
real(eightbytereal), intent(in) :: limits(2)
real(eightbytereal), intent(inout) :: value
logical :: outofrange
!
! This function checks if value is within <limits(1:2)>, where
! <limits(1)> is less than <limits(2)>. If <value> is not within those
! limits, <outofrange> is set to .true.
!
! If either of the limits is NaN, no check is performed at that limit.
!
! Arguments:
!  limits     : minimum and maximum allowed value
!  value      : value to be checked
!  outofrange : .true. if value is outside limits, .false. otherwise.
!-----------------------------------------------------------------------
outofrange = (value < limits(1) .or. value > limits(2))
end function outofrange

!***********************************************************************
!*nint1 -- Round 8-byte real to 1-byte integer
!+
elemental function nint1 (x)
integer(onebyteint) :: nint1
real(eightbytereal), intent(in) :: x
!
! This elemental function rounds an 8-byte real to a 1-byte integer.
! If the real is out of range, or NaN, the returned value is 127.
! Since this function is elemental, it can be applied to arrays as well.
!-----------------------------------------------------------------------
integer(onebyteint), parameter :: imax = huge(0_onebyteint)
real(eightbytereal), parameter :: xmin = -imax-1.5d0, xmax = imax+0.5d0
if (x > xmin .and. x < xmax) then
	nint1 = nint(x,onebyteint)
else ! Out of range or NaN
	nint1 = imax
endif
end function nint1

!***********************************************************************
!*nint2 -- Round 8-byte real to 2-byte integer
!+
elemental function nint2 (x)
integer(twobyteint) :: nint2
real(eightbytereal), intent(in) :: x
!
! This elemental function rounds an 8-byte real to a 2-byte integer.
! If the real is out of range, or NaN, the returned value is 32767.
! Since this function is elemental, it can be applied to arrays as well.
!-----------------------------------------------------------------------
integer(twobyteint), parameter :: imax = huge(0_twobyteint)
real(eightbytereal), parameter :: xmin = -imax-1.5d0, xmax = imax+0.5d0
if (x > xmin .and. x < xmax) then
	nint2 = nint(x,twobyteint)
else ! Out of range or NaN
	nint2 = imax
endif
end function nint2

!***********************************************************************
!*nint4 -- Round 8-byte real to 4-byte integer
!+
elemental function nint4 (x)
integer(fourbyteint) :: nint4
real(eightbytereal), intent(in) :: x
!
! This elemental function rounds an 8-byte real to a 4-byte integer.
! If the real is out of range, or NaN, the returned value is 2147483647.
! Since this function is elemental, it can be applied to arrays as well.
!-----------------------------------------------------------------------
integer(fourbyteint), parameter :: imax = huge(0_fourbyteint)
real(eightbytereal), parameter :: xmin = -imax-1.5d0, xmax = imax+0.5d0
if (x > xmin .and. x < xmax) then
	nint4 = nint(x,fourbyteint)
else ! Out of range or NaN
	nint4 = imax
endif
end function nint4

!***********************************************************************
!*bit_transfer -- Transfer the bit pattern of integer part of double
!+
elemental subroutine bit_transfer (x)
real(eightbytereal), intent(inout) :: x
if (little_endian) then
	x = transfer((/nint4(x),0_fourbyteint/),0d0)
else
	x = transfer((/0_fourbyteint,nint4(x)/),0d0)
endif
end subroutine bit_transfer

!***********************************************************************
!*isnan -- Check if double precision number is a NaN
!+
elemental function isnan_ (x)
real(eightbytereal), intent(in) :: x
logical :: isnan_
!
! This elemental function checks if a 8-byte real is a NaN.
! It is added here, since it is not standard Fortran 90, though GNU
! Fortran and HP Fortran have it.
! Since this function is elemental, it can be applied to arrays as well.
!-----------------------------------------------------------------------
isnan_ = (x /= x)
end function isnan_

!***********************************************************************
!*cross_product -- Compute cross product of two 3-D vectors
!+
pure function cross_product (a, b) result(c)
real(eightbytereal), intent(in) :: a(3), b(3)
real(eightbytereal) :: c(3)
!
! This function returns the vector obtained by computing the cross
! product of two 3-dimensional vectors.
!-----------------------------------------------------------------------
c(1) = a(2) * b(3) - a(3) * b(2)
c(2) = a(3) * b(1) - a(1) * b(3)
c(3) = a(1) * b(2) - a(2) * b(1)
end function cross_product

!***********************************************************************
!*iqsort -- Make a quick sort of an INTEGER*4 array
!+
subroutine iqsort (idx, val, nr)
use typesizes
integer(fourbyteint), intent(inout) :: idx(nr)
integer(fourbyteint), intent(in) :: val(:), nr
!
! This routine quick-sorts an integer array <idx> according to the
! corresponding value in array <val> of type integer.
! The array <idx> contains <nr> pointers to the values in array <val>,
! which does not have to be equally large.
!
! Arguments:
!  idx (input) : One-dimensional array of index numbers
!     (output) : Row of index numbers sorted on corresponding value
!  val (input) : One-dimensional array of values
!  nr  (input) : Number of indices/values
!
! Example 1:
! Assume you have 6 values 100, 10, 11, 21, 17, and 90, stored in array
! <val>. These values have to be sorted in ascending order. Your input
! will be like this:
!
!   idx    1    2    3    4    5    6
!   val  100   10   11   21   17   90
!    nr    6
!
! After running iqsort, the output will look like this:
!
!   idx    2    3    5    4    6    1
!   val  100   10   11   21   17   90
!    nr    6
!
! Note that the array <val> has not been changed, but that <idx> is sorted by
! the order in which <val> should be sorted. You may print the values in
! the ascending order as follows:
!
!     do i=1,nr
!        write (*,*) val(idx(i))
!     enddo
!
! Example 2:
! It is also possible that the indices are not in logical order. As long as
! they point to the respective locations of the values in array <val>, the
! sorting will be done accordingly. Assume you have the following input:
! (values ** are irrelevant)
!
!   idx    1    2    4    5    6    8
!   val  100   10   **   21   17   90   **   1
!    nr    6
!
! Then after running iqsort, the result will be:
!
!   idx    8    2    5    4    6    1
!   val  100   10   **   21   17   90   **   1
!    nr    6
!
! Printing the values in ascending order after this goes the same as in
! Example 1.
!-----------------------------------------------------------------------
integer(fourbyteint), parameter :: m = 7, nstack = 2000
integer(fourbyteint) :: i,indxt,ir,itemp,j,jstack,k,l,istack(nstack)
integer(fourbyteint) :: a
jstack = 0
l = 1
ir = nr
do
	if (ir-l < m) then
		jloop: do j = l+1,ir
			indxt = idx(j)
			a = val(indxt)
			do i = j-1,1,-1
				if (val(idx(i)) < a) then
					idx(i+1) = indxt
					cycle jloop
				endif
				idx(i+1) = idx(i)
			enddo
			i = 0
			idx(i+1)=indxt
		enddo jloop
		if (jstack == 0) return
		ir = istack(jstack)
		l = istack(jstack-1)
		jstack = jstack-2
	else
		k = (l+ir) / 2
		itemp = idx(k)
		idx(k) = idx(l+1)
		idx(l+1) = itemp
		if (val(idx(l+1)) > val(idx(ir))) then
			itemp = idx(l+1)
			idx(l+1) = idx(ir)
			idx(ir) = itemp
		endif
		if (val(idx(l)) > val(idx(ir))) then
			itemp = idx(l)
			idx(l) = idx(ir)
			idx(ir) = itemp
		endif
		if (val(idx(l+1)) > val(idx(l))) then
			itemp = idx(l+1)
			idx(l+1) = idx(l)
			idx(l) = itemp
		endif
		i = l+1
		j = ir
		indxt = idx(l)
		a = val(indxt)
		do
			do
				i = i+1
				if (val(idx(i)) >= a) exit
			enddo
			do
				j = j-1
				if (val(idx(j)) <= a) exit
			enddo
			if (j < i) exit
			itemp=idx(i)
			idx(i)=idx(j)
			idx(j)=itemp
		enddo
		idx(l) = idx(j)
		idx(j) = indxt
		jstack = jstack+2
		if (jstack > nstack) stop 'NSTACK too small in IQSORT'
		if (ir-i+1 >= j-1) then
			istack(jstack) = ir
			istack(jstack-1) = i
			ir = j-1
		else
			istack(jstack) = j-1
			istack(jstack-1) = l
			l = i
		endif
	endif
enddo
end subroutine iqsort

!***********************************************************************
!*mean_variance -- Compute mean and standard deviation of a series
!+
pure subroutine mean_variance (x, mean, variance)
real(eightbytereal), intent(in) :: x(:)
real(eightbytereal), intent(out) :: mean, variance
!
! This routine computes the mean and variance of a series
! of values <x> using the method proposed by West (1979), since it is
! more stable in the way it computes the variance.
!
! This routine does not check for NaN values.
!
! Reference:
!  West, D. H. D
!  Updating mean and variance estimates: an improved method
!  Communications of the ACM, 22(9), 532-535, 1979
!
! Arguments:
!  x        : Series of values
!  mean     : Mean of series <x>
!  variance : Variance of series <x>
!-----------------------------------------------------------------------
real(eightbytereal) :: q, r, sum2
integer(fourbyteint) :: i, n
n = size(x)
if (n == 0) then
	mean = nan
	variance = mean
	return
else if (n == 1) then
	mean = x(1)
	variance = nan
	return
endif
mean = 0d0
sum2 = 0d0
do i = 1,n
	q = x(i) - mean
	r = q / i
	mean = mean + r
	sum2 = sum2 + r * q * (i-1)
enddo
variance = sum2/(n-1)
end subroutine mean_variance

!***********************************************************************
!*is_number -- Is string a number?
!+
pure function is_number (string)
character(len=*), intent(in) :: string
logical :: is_number
!
! This function determines if the character string supplied is a number
! (or starts with a number followed by whitespace).
! Both floating point (1.0, 1d9, -1e-10) and integers (0, -5) are allowed.
! 'NaN' or 'nan' is considered a number as well.
!
! Arguments:
!  string   : Input character string
!  is_number: Return value. True is string is a number
!-----------------------------------------------------------------------
integer :: ios
real(eightbytereal) :: val
read (string,*,iostat=ios) val
is_number = (ios == 0)
end function is_number

!***********************************************************************
!*next_word -- Get next word from string
!+
function next_word (string, i0, i1)
character(len=*), intent(in) :: string
integer, intent(inout) :: i0,i1
logical :: next_word
!
! This routine scans <string> and finds the next word in <string>
! after index <i1>. A word is considered anything between delimiters
! space, comma, or slash. Multiple spaces are seen as one delimeter,
! but not multiple commas or slashes.
! Upon return <i0> returns the start of the next word, and <i1> returns
! the end of the next word PLUS 1. Hence, and empy next word will have
! i0 == i1.
!
! When scanning for all words in a string, initialize i1 = 0.
!
! If another word is found:
!   <next_word> = .true.
!   <i0> is the start index of the next word in <string>
!   <i1> is the end index + 1 of the next word in <string>
! Otherwise:
!   <next_word> = .false.
!   <i0> and <i1> are both zero
!
! Arguments:
!  string   : Input character string
!  i0       : Start of word found (zero when none)
!  i1       : Input: position of last delimeter
!             output: position of the next delimeter
!  next_word: .true. is word found, .false. otherwise
!-----------------------------------------------------------------------
integer :: l,i
l = len(string)

! Scan beyond leading ignored whitespace
do i = i1+1,l
	if (string(i:i) /= ' ') exit
enddo

! End of string reached, no words found
if (i > l) then
	i0 = 0
	i1 = 0
	next_word = .false.
	return
endif

! Find end of next word
i0 = i
do i = i0,l
	if (string(i:i) == ' ' .or. string(i:i) == ',' .or. string(i:i) == '/') exit
enddo
i1 = i
next_word = .true.
end function next_word


!***********************************************************************
!*mean_1hz -- Compute mean and rms of multi-Hz array
!+
subroutine mean_1hz (y, valid, mean, rms)
real(eightbytereal), intent(in) :: y(:,:)
logical, intent(in) :: valid(:,:)
real(eightbytereal), intent(out) :: mean(:), rms(:)
!
! Compute mean and stddev values from multi-Hz array <y(m,n)> where <m> is
! the number of measurements per "second" (usually 20) and <n> is the
! number of 1-Hz measurements in the array. Output are the mean values,
! stored in <mean(n)> and the standard deviations stored in <rms(n)>.
!
! Only the values of <y> for which the corresponding value of <valid> is
! true are used.
!
! Arguments:
!  y     : Input array of dimension (m,n)
!  valid : Indicates which values of y to use
!  mean  : Average of y per 1-Hz, dimension n
!  rms   : Standard deviation of 1-Hz, dimension n
!-
integer(fourbyteint) :: i, j, n
do j = 1,size(y,2)
	mean(j) = 0d0
	rms(j) = 0d0
	n = 0
	do i = 1,size(y,1)
		if (valid(i,j)) then
			n = n + 1
			mean(j) = mean(j) + y(i,j)
			rms(j) = rms(j) + y(i,j)**2
		endif
	enddo
	if (n < 1) then
		mean(j) = nan
	else
		mean(j) = mean(j) / n
	endif
	if (n < 2) then
		rms(j) = nan
	else
		rms(j) = sqrt ((rms(j) - n * mean(j)**2) / (n - 1))
	endif
enddo
end subroutine mean_1hz

!***********************************************************************
!*trend_1hz -- Compute mean and rms of multi-Hz array with trend removal
!+
subroutine trend_1hz (x, x0, y, valid, mean, rms)
real(eightbytereal), intent(in) :: x(:,:), x0(:), y(:,:)
logical, intent(in) :: valid(:,:)
real(eightbytereal), intent(out) :: mean(:), rms(:)
!
! Compute mean and stddev values from multi-Hz array <y(m,n)> where <m> is
! the number of measurements per "second" (usually 20) and <n> is the
! number of 1-Hz measurements in the array. Output are the mean values,
! stored in <mean(n)> and the standard deviations stored in <rms(n)>.
!
! A trend is removed while computing the mean at x-coordinate <x0>. <x>
! indicates the x-coordinate corresponding to the array <y>.
!
! Only the values of <y> for which the corresponding value of <valid> is
! true are used.
!
! Arguments:
!  x     : x-coordinate belonging to the values y
!  x0    : x-coordinate to compute mean
!  y     : Input array of dimension (m,n)
!  valid : Indicates which values of y to use
!  mean  : Average of y per 1-Hz, dimension n
!  rms   : Standard deviation of 1-Hz, dimension n
!-
real(eightbytereal) :: sumx,sumy,sumxx,sumxy,sumyy,uxx,uxy,uyy,a,b,xx
integer(fourbyteint) :: i, j, n
do j = 1,size(y,2)
	n = 0
	sumx = 0d0
	sumy = 0d0
	sumxx = 0d0
	sumxy = 0d0
	sumyy = 0d0
	do i = 1,size(y,1)
		if (valid(i,j)) then
			xx = x(i,j) - x0(j)
			sumx = sumx + xx
			sumy = sumy + y(i,j)
			sumxx = sumxx + xx*xx
			sumxy = sumxy + xx*y(i,j)
			sumyy = sumyy + y(i,j)*y(i,j)
			n = n + 1
		endif
	enddo
	if (n < 1) then
		mean(j) = nan
	else
		uxx = n * sumxx - sumx * sumx
		uxy = n * sumxy - sumx * sumy
		uyy = n * sumyy - sumy * sumy
		b = uxy / uxx
		a = (sumy - b*sumx) / n
		mean(j) = a
	endif
	if (n < 3) then
		rms(j) = nan
	else
		rms(j) = sqrt ((sumyy - a * sumy - b * sumxy) / (n-2))
	endif
enddo
end subroutine trend_1hz

!***********************************************************************

elemental function d_int1 (i)
integer(onebyteint), intent(in) :: i
real(eightbytereal) :: d_int1
if (i == huge(0_onebyteint)) then
	d_int1 = nan
else
	d_int1 = i
endif
end function d_int1

elemental function d_int2 (i)
integer(twobyteint), intent(in) :: i
real(eightbytereal) :: d_int2
if (i == huge(0_twobyteint)) then
	d_int2 = nan
else
	d_int2 = i
endif
end function d_int2

elemental function d_int4 (i)
integer(fourbyteint), intent(in) :: i
real(eightbytereal) :: d_int4
if (i == huge(0_fourbyteint)) then
	d_int4 = nan
else
	d_int4 = i
endif
end function d_int4

pure subroutine read_val_dble (string, val, translate)
character(len=*), intent(in) :: string
real(eightbytereal), intent(out) :: val(:)
character(len=*), intent(in), optional :: translate
character(len=len(string)) :: temp
integer :: i,j
if (present(translate)) then
	do i = 1,len(string)
		j = index(translate, string(i:i))
		if (j > 0) then
			temp(i:i) = ','
		else
			temp(i:i) = string(i:i)
		endif
	enddo
	read (temp, *, iostat=i) val
else
	read (string, *, iostat=i) val
endif
end subroutine read_val_dble

pure subroutine read_val_int (string, val, translate)
character(len=*), intent(in) :: string
integer(fourbyteint), intent(out) :: val(:)
character(len=*), intent(in), optional :: translate
character(len=len(string)) :: temp
integer :: i,j
if (present(translate)) then
	do i = 1,len(string)
		j = index(translate, string(i:i))
		if (j > 0) then
			temp(i:i) = ','
		else
			temp(i:i) = string(i:i)
		endif
	enddo
	read (temp, *, iostat=i) val
else
	read (string, *, iostat=i) val
endif
end subroutine read_val_int

end module rads_misc
