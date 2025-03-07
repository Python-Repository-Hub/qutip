#cython: language_level=3

import numpy as np
import qutip.settings as qset
cimport numpy as cnp
cimport cython
from libcpp cimport bool

cdef extern from "<complex>" namespace "std" nogil:
    double complex conj(double complex x)
    double         real(double complex)
    double         imag(double complex)
    double         abs(double complex)

include "sparse_routines.pxi"

@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_add(complex[::1] dataA, int[::1] indsA, int[::1] indptrA,
             complex[::1] dataB, int[::1] indsB, int[::1] indptrB,
             int nrows, int ncols,
             int Annz, int Bnnz,
             double complex alpha = 1):

    """
    Adds two sparse CSR matries. Like SciPy, we assume the worse case
    for the fill A.nnz + B.nnz.
    """
    cdef int worse_fill = Annz + Bnnz
    cdef int nnz
    #Both matrices are zero mats
    if Annz == 0 and Bnnz == 0:
        return fast_csr_matrix(([], [], []), shape=(nrows,ncols))
    #A is the zero matrix
    elif Annz == 0:
        return fast_csr_matrix((alpha*np.asarray(dataB), indsB, indptrB),
                            shape=(nrows,ncols))
    #B is the zero matrix
    elif Bnnz == 0:
        return fast_csr_matrix((dataA, indsA, indptrA),
                            shape=(nrows,ncols))
    # Out CSR_Matrix
    cdef CSR_Matrix out
    init_CSR(&out, worse_fill, nrows, ncols, worse_fill)

    nnz = _zcsr_add_core(&dataA[0], &indsA[0], &indptrA[0],
                     &dataB[0], &indsB[0], &indptrB[0],
                     alpha,
                     &out,
                     nrows, ncols)
    #Shorten data and indices if needed
    if out.nnz > nnz:
        shorten_CSR(&out, nnz)
    return CSR_to_scipy(&out)


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_add(CSR_Matrix * A, CSR_Matrix * B, CSR_Matrix * C, double complex alpha):
    """
    Adds two sparse CSR matries. Like SciPy, we assume the worse case
    for the fill A.nnz + B.nnz.
    """
    cdef int worse_fill = A.nnz + B.nnz
    cdef int nrows = A.nrows
    cdef int ncols = A.ncols
    cdef int nnz
    init_CSR(C, worse_fill, nrows, ncols, worse_fill)

    nnz = _zcsr_add_core(A.data, A.indices, A.indptr,
                     B.data, B.indices, B.indptr,
                     alpha, C, nrows, ncols)
    #Shorten data and indices if needed
    if C.nnz > nnz:
        shorten_CSR(C, nnz)



@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _zcsr_add_core(double complex * Adata, int * Aind, int * Aptr,
                     double complex * Bdata, int * Bind, int * Bptr,
                     double complex alpha,
                     CSR_Matrix * C,
                     int nrows, int ncols) nogil:

    cdef int j1, j2, kc = 0
    cdef int ka, kb, ka_max, kb_max
    cdef size_t ii
    cdef double complex tmp
    C.indptr[0] = 0
    if alpha != 1:
        for ii in range(nrows):
            ka = Aptr[ii]
            kb = Bptr[ii]
            ka_max = Aptr[ii+1]-1
            kb_max = Bptr[ii+1]-1
            while (ka <= ka_max) or (kb <= kb_max):
                if ka <= ka_max:
                    j1 = Aind[ka]
                else:
                    j1 = ncols+1

                if kb <= kb_max:
                    j2 = Bind[kb]
                else:
                    j2 = ncols+1

                if j1 == j2:
                    tmp = Adata[ka] + alpha*Bdata[kb]
                    if tmp != 0:
                        C.data[kc] = tmp
                        C.indices[kc] = j1
                        kc += 1
                    ka += 1
                    kb += 1
                elif j1 < j2:
                    C.data[kc] = Adata[ka]
                    C.indices[kc] = j1
                    ka += 1
                    kc += 1
                elif j1 > j2:
                    C.data[kc] = alpha*Bdata[kb]
                    C.indices[kc] = j2
                    kb += 1
                    kc += 1

            C.indptr[ii+1] = kc
    else:
        for ii in range(nrows):
            ka = Aptr[ii]
            kb = Bptr[ii]
            ka_max = Aptr[ii+1]-1
            kb_max = Bptr[ii+1]-1
            while (ka <= ka_max) or (kb <= kb_max):
                if ka <= ka_max:
                    j1 = Aind[ka]
                else:
                    j1 = ncols+1

                if kb <= kb_max:
                    j2 = Bind[kb]
                else:
                    j2 = ncols+1

                if j1 == j2:
                    tmp = Adata[ka] + Bdata[kb]
                    if tmp != 0:
                        C.data[kc] = tmp
                        C.indices[kc] = j1
                        kc += 1
                    ka += 1
                    kb += 1
                elif j1 < j2:
                    C.data[kc] = Adata[ka]
                    C.indices[kc] = j1
                    ka += 1
                    kc += 1
                elif j1 > j2:
                    C.data[kc] = Bdata[kb]
                    C.indices[kc] = j2
                    kb += 1
                    kc += 1

            C.indptr[ii+1] = kc
    return kc



@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_mult(object A, object B, int sorted = 1):

    cdef complex [::1] dataA = A.data
    cdef int[::1] indsA = A.indices
    cdef int[::1] indptrA = A.indptr
    cdef int Annz = A.nnz

    cdef complex [::1] dataB = B.data
    cdef int[::1] indsB = B.indices
    cdef int[::1] indptrB = B.indptr
    cdef int Bnnz = B.nnz

    cdef int nrows = A.shape[0]
    cdef int ncols = B.shape[1]

    #Both matrices are zero mats
    if Annz == 0 or Bnnz == 0:
        return fast_csr_matrix(shape=(nrows,ncols))

    cdef int nnz
    cdef CSR_Matrix out

    nnz = _zcsr_mult_pass1(&dataA[0], &indsA[0], &indptrA[0],
                     &dataB[0], &indsB[0], &indptrB[0],
                     nrows, ncols)

    if nnz == 0:
        return fast_csr_matrix(shape=(nrows,ncols))

    init_CSR(&out, nnz, nrows, ncols)
    _zcsr_mult_pass2(&dataA[0], &indsA[0], &indptrA[0],
                     &dataB[0], &indsB[0], &indptrB[0],
                     &out,
                     nrows, ncols)

    #Shorten data and indices if needed
    if out.nnz > out.indptr[out.nrows]:
        shorten_CSR(&out, out.indptr[out.nrows])

    if sorted:
        sort_indices(&out)
    return CSR_to_scipy(&out)



@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_mult(CSR_Matrix * A, CSR_Matrix * B, CSR_Matrix * C):

    nnz = _zcsr_mult_pass1(A.data, A.indices, A.indptr,
                 B.data, B.indices, B.indptr,
                 A.nrows, B.ncols)

    init_CSR(C, nnz, A.nrows, B.ncols)
    _zcsr_mult_pass2(A.data, A.indices, A.indptr,
                 B.data, B.indices, B.indptr,
                 C,
                 A.nrows, B.ncols)

    #Shorten data and indices if needed
    if C.nnz > C.indptr[C.nrows]:
        shorten_CSR(C, C.indptr[C.nrows])
    sort_indices(C)


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _zcsr_mult_pass1(double complex * Adata, int * Aind, int * Aptr,
                     double complex * Bdata, int * Bind, int * Bptr,
                     int nrows, int ncols) nogil:

    cdef int j, k, nnz = 0
    cdef size_t ii,jj,kk
    #Setup mask array
    cdef int * mask = <int *>PyDataMem_NEW(ncols*sizeof(int))
    for ii in range(ncols):
        mask[ii] = -1
    #Pass 1
    for ii in range(nrows):
        for jj in range(Aptr[ii], Aptr[ii+1]):
            j = Aind[jj]
            for kk in range(Bptr[j], Bptr[j+1]):
                k = Bind[kk]
                if mask[k] != ii:
                    mask[k] = ii
                    nnz += 1
    PyDataMem_FREE(mask)
    return nnz


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_mult_pass2(double complex * Adata, int * Aind, int * Aptr,
                     double complex * Bdata, int * Bind, int * Bptr,
                     CSR_Matrix * C,
                     int nrows, int ncols) nogil:

    cdef int head, length, temp, j, k, nnz = 0
    cdef size_t ii,jj,kk
    cdef double complex val
    cdef double complex * sums = <double complex *>PyDataMem_NEW_ZEROED(ncols, sizeof(double complex))
    cdef int * nxt = <int *>PyDataMem_NEW(ncols*sizeof(int))
    for ii in range(ncols):
        nxt[ii] = -1

    C.indptr[0] = 0
    for ii in range(nrows):
        head = -2
        length = 0
        for jj in range(Aptr[ii], Aptr[ii+1]):
            j = Aind[jj]
            val = Adata[jj]
            for kk in range(Bptr[j], Bptr[j+1]):
                k = Bind[kk]
                sums[k] += val*Bdata[kk]
                if nxt[k] == -1:
                    nxt[k] = head
                    head = k
                    length += 1

        for jj in range(length):
            if sums[head] != 0:
                C.indices[nnz] = head
                C.data[nnz] = sums[head]
                nnz += 1
            temp = head
            head = nxt[head]
            nxt[temp] = -1
            sums[temp] = 0

        C.indptr[ii+1] = nnz

    #Free temp arrays
    PyDataMem_FREE(sums)
    PyDataMem_FREE(nxt)


@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_kron(object A, object B):
    """
    Computes the kronecker product between two complex
    sparse matrices in CSR format.
    """
    cdef complex[::1] dataA = A.data
    cdef int[::1] indsA = A.indices
    cdef int[::1] indptrA = A.indptr
    cdef int rowsA = A.shape[0]
    cdef int colsA = A.shape[1]

    cdef complex[::1] dataB = B.data
    cdef int[::1] indsB = B.indices
    cdef int[::1] indptrB = B.indptr
    cdef int rowsB = B.shape[0]
    cdef int colsB = B.shape[1]

    cdef int out_nnz = _safe_multiply(indptrA[rowsA], indptrB[rowsB])
    cdef int rows_out = _safe_multiply(rowsA, rowsB)
    cdef int cols_out = _safe_multiply(colsA, colsB)

    cdef CSR_Matrix out
    init_CSR(&out, out_nnz, rows_out, cols_out)

    _zcsr_kron_core(&dataA[0], &indsA[0], &indptrA[0],
                    &dataB[0], &indsB[0], &indptrB[0],
                    &out,
                    rowsA, rowsB, colsB)
    return CSR_to_scipy(&out)


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_kron(CSR_Matrix * A, CSR_Matrix * B, CSR_Matrix * C) except *:
    """
    Computes the kronecker product between two complex
    sparse matrices in CSR format.
    """

    cdef int out_nnz = _safe_multiply(A.nnz, B.nnz)
    cdef int rows_out = _safe_multiply(A.nrows, B.nrows)
    cdef int cols_out = _safe_multiply(A.ncols, B.ncols)

    init_CSR(C, out_nnz, rows_out, cols_out)

    _zcsr_kron_core(A.data, A.indices, A.indptr,
                    B.data, B.indices, B.indptr,
                    C,
                    A.nrows, B.nrows, B.ncols)


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_kron_core(double complex * dataA, int * indsA, int * indptrA,
                     double complex * dataB, int * indsB, int * indptrB,
                     CSR_Matrix * out,
                     int rowsA, int rowsB, int colsB) nogil:
    cdef size_t ii, jj, ptrA, ptr
    cdef int row = 0
    cdef int ptr_start, ptr_end
    cdef int row_startA, row_endA, row_startB, row_endB, distA, distB, ptrB

    for ii in range(rowsA):
        row_startA = indptrA[ii]
        row_endA = indptrA[ii+1]
        distA = row_endA - row_startA

        for jj in range(rowsB):
            row_startB = indptrB[jj]
            row_endB = indptrB[jj+1]
            distB = row_endB - row_startB

            ptr_start = out.indptr[row]
            ptr_end = ptr_start + distB

            out.indptr[row+1] = out.indptr[row] + distA * distB
            row += 1

            for ptrA in range(row_startA, row_endA):
                ptrB = row_startB
                for ptr in range(ptr_start, ptr_end):
                    out.indices[ptr] = indsA[ptrA] * colsB + indsB[ptrB]
                    out.data[ptr] = dataA[ptrA] * dataB[ptrB]
                    ptrB += 1

                ptr_start += distB
                ptr_end += distB


@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_transpose(object A):
    """
    Transpose of a sparse matrix in CSR format.
    """
    cdef complex[::1] data = A.data
    cdef int[::1] ind = A.indices
    cdef int[::1] ptr = A.indptr
    cdef int nrows = A.shape[0]
    cdef int ncols = A.shape[1]

    cdef CSR_Matrix out
    init_CSR(&out, data.shape[0], ncols, nrows)

    _zcsr_trans_core(&data[0], &ind[0], &ptr[0],
                    &out, nrows, ncols)
    return CSR_to_scipy(&out)


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_transpose(CSR_Matrix * A, CSR_Matrix * B):
    """
    Transpose of a sparse matrix in CSR format.
    """
    init_CSR(B, A.nnz, A.ncols, A.nrows)

    _zcsr_trans_core(A.data, A.indices, A.indptr, B, A.nrows, A.ncols)

@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_trans_core(double complex * data, int * ind, int * ptr,
                     CSR_Matrix * out,
                     int nrows, int ncols) nogil:

    cdef int k, nxt
    cdef size_t ii, jj

    for ii in range(nrows):
        for jj in range(ptr[ii], ptr[ii+1]):
            k = ind[jj] + 1
            out.indptr[k] += 1

    for ii in range(ncols):
        out.indptr[ii+1] += out.indptr[ii]

    for ii in range(nrows):
        for jj in range(ptr[ii], ptr[ii+1]):
            k = ind[jj]
            nxt = out.indptr[k]
            out.data[nxt] = data[jj]
            out.indices[nxt] = ii
            out.indptr[k] = nxt + 1

    for ii in range(ncols,0,-1):
        out.indptr[ii] = out.indptr[ii-1]

    out.indptr[0] = 0



@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_adjoint(object A):
    """
    Adjoint of a sparse matrix in CSR format.
    """
    cdef complex[::1] data = A.data
    cdef int[::1] ind = A.indices
    cdef int[::1] ptr = A.indptr
    cdef int nrows = A.shape[0]
    cdef int ncols = A.shape[1]

    cdef CSR_Matrix out
    init_CSR(&out, data.shape[0], ncols, nrows)

    _zcsr_adjoint_core(&data[0], &ind[0], &ptr[0],
                        &out, nrows, ncols)
    return CSR_to_scipy(&out)


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_adjoint(CSR_Matrix * A, CSR_Matrix * B):
    """
    Adjoint of a sparse matrix in CSR format.
    """
    init_CSR(B, A.nnz, A.ncols, A.nrows)

    _zcsr_adjoint_core(A.data, A.indices, A.indptr,
                        B, A.nrows, A.ncols)


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _zcsr_adjoint_core(double complex * data, int * ind, int * ptr,
                     CSR_Matrix * out,
                     int nrows, int ncols) nogil:

    cdef int k, nxt
    cdef size_t ii, jj

    for ii in range(nrows):
        for jj in range(ptr[ii], ptr[ii+1]):
            k = ind[jj] + 1
            out.indptr[k] += 1

    for ii in range(ncols):
        out.indptr[ii+1] += out.indptr[ii]

    for ii in range(nrows):
        for jj in range(ptr[ii], ptr[ii+1]):
            k = ind[jj]
            nxt = out.indptr[k]
            out.data[nxt] = conj(data[jj])
            out.indices[nxt] = ii
            out.indptr[k] = nxt + 1

    for ii in range(ncols,0,-1):
        out.indptr[ii] = out.indptr[ii-1]

    out.indptr[0] = 0


cdef inline bint _conj_feq(double complex a, double complex b, double tolsq) nogil:
    """
    Test floating-point approximate equality of one complex number with the
    complex conjugate of the other, up to a certain absolute tolerance
    (provided squared to reduce FLOPS required).  Since the square is
    monotonic and we're comparing values close to 0, we're safe from numerical
    precision issues, and avoiding the square root is a big speedup.
    """
    cdef double re = a.real - b.real
    cdef double im = a.imag + b.imag
    return re*re + im*im < tolsq

cdef inline bint _feq_zero(double complex a, double tolsq) nogil:
    """Test complex floating-point approximate equality to zero."""
    return a.real*a.real + a.imag*a.imag < tolsq


@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_isherm(object A not None, double tol = qset.atol):
    """
    Determines if a given input sparse CSR matrix is Hermitian to within a
    specified floating-point tolerance.

    Parameters
    ----------
    A : csr_matrix
        Input sparse matrix.
    tol : float (default is atol from settings)
        Desired tolerance value.

    Returns
    -------
    isherm : bool
        True if matrix is Hermitian, False otherwise.

    Notes
    -----
    This implementation is esentially an adjoint calulation where the data and
    indices are not stored, but checked elementwise to see if they match those
    of the input matrix.  Thus we do not need to build the actual adjoint.
    Here we only need a temp array of output indptr.
    """
    cdef complex[::1] data = A.data
    cdef int[::1] col_index = A.indices
    cdef int[::1] row_index = A.indptr
    cdef int nrows = A.shape[0]
    cdef int ncols = A.shape[1]
    cdef double tolsq=tol*tol
    cdef int col, nxt
    cdef size_t row, ptr

    if nrows != ncols:
        return False

    cdef int *out_row_index = <int *>PyDataMem_NEW_ZEROED(ncols+1, sizeof(int))
    if not out_row_index:
        raise MemoryError
    try:
        for row in range(nrows):
            for ptr in range(row_index[row], row_index[row + 1]):
                out_row_index[col_index[ptr] + 1] += 1
        for row in range(nrows):
            out_row_index[row + 1] += out_row_index[row]
            if out_row_index[row + 1] != row_index[row + 1]:
                # Structures are not the same, but it could still be Hermitian
                # if any value is less than the tolerance.  That is the
                # worst-case scenario, so we sacrifice its speed in favour of
                # returning faster for the more common failure cases.
                for ptr in range(row_index[nrows]):
                    if _feq_zero(data[ptr], tolsq):
                        return _zcsr_isherm_full(data, col_index, row_index, nrows, tolsq)
                return False
        for row in range(nrows):
            for ptr in range(row_index[row], row_index[row + 1]):
                col = col_index[ptr]
                nxt = out_row_index[col]
                out_row_index[col] += 1
                # We tested the structure already, so we can guarantee that
                # these two elements correspond.
                if not _conj_feq(data[ptr], data[nxt], tolsq):
                    return False
        return True
    finally:
        PyDataMem_FREE(out_row_index)

@cython.boundscheck(False)
@cython.wraparound(False)
cdef bint _zcsr_isherm_full(
    double complex [::1] data, int [::1] col_index, int [::1] row_index,
    int size, double tolsq,
) except 2:
    """
    Full, structural test for Hermicity of a matrix.  We assume that the input
    matrix has already had its shape tested (must be square).

    This test is only necessary when there is at least one value which is less
    than the tolerance, and needed to be compared to an implicit zero.  In
    general it is less efficient than the other test, and allocates more
    memory.
    """
    cdef CSR_Matrix transpose
    cdef size_t row, ptr_a, ptr_b, col_a, col_b
    cdef int nnz = row_index[size]
    # We can't reuse the calculated `indptr` array from the previous function,
    # because that is modified in-place during execution.
    init_CSR(&transpose, nnz, size)
    _zcsr_trans_core(&data[0], &col_index[0], &row_index[0], &transpose, size, size)
    try:
        for row in range(size):
            ptr_a, ptr_a_end = row_index[row], row_index[row + 1]
            ptr_b, ptr_b_end = transpose.indptr[row], transpose.indptr[row + 1]
            while ptr_a < ptr_a_end and ptr_b < ptr_b_end:
                # Doing this on every loop actually involves a few more
                # de-references than are strictly necessary, but just
                # simplifies the logic checking for the end of the row.
                col_a = col_index[ptr_a]
                col_b = transpose.indices[ptr_b]
                if col_a == col_b:
                    if not _conj_feq(data[ptr_a], transpose.data[ptr_b], tolsq):
                        return False
                    ptr_a += 1
                    ptr_b += 1
                elif col_a < col_b:
                    if not _feq_zero(data[ptr_a], tolsq):
                        return False
                    ptr_a += 1
                else:
                    if not _feq_zero(transpose.data[ptr_b], tolsq):
                        return False
                    ptr_b += 1
            for ptr_a in range(ptr_a, ptr_a_end):
                if not _feq_zero(data[ptr_a], tolsq):
                    return False
            for ptr_b in range(ptr_b, ptr_b_end):
                if not _feq_zero(transpose.data[ptr_b], tolsq):
                    return False
        return True
    finally:
        free_CSR(&transpose)


# Exception signal value should be something we only return rarely.
@cython.overflowcheck(True)
cdef int _safe_multiply(int A, int B) except? -1:
    """
    Computes A*B and checks for overflow.
    """
    cdef int C = A*B
    return C



@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_trace(object A, bool isherm):
    cdef complex[::1] data = A.data
    cdef int[::1] ind = A.indices
    cdef int[::1] ptr = A.indptr
    cdef int nrows = ptr.shape[0]-1
    cdef size_t ii, jj
    cdef complex tr = 0

    for ii in range(nrows):
        for jj in range(ptr[ii], ptr[ii+1]):
            if ind[jj] == ii:
                tr += data[jj]
                break
    if imag(tr) == 0 or isherm:
        return real(tr)
    else:
        return tr


@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_proj(object A, bool is_ket=1):
    """
    Computes the projection operator
    from a given ket or bra vector
    in CSR format.  The flag 'is_ket'
    is True if passed a ket.

    This is ~3x faster than doing the
    conjugate transpose and sparse multiplication
    directly.  Also, does not need a temp matrix.
    """
    cdef complex[::1] data = A.data
    cdef int[::1] ind = A.indices
    cdef int[::1] ptr = A.indptr
    cdef int nrows
    cdef int nnz

    cdef int offset = 0, new_idx, count, change_idx
    cdef size_t jj, kk

    if is_ket:
        nrows = A.shape[0]
        nnz = ptr[nrows]
    else:
        nrows = A.shape[1]
        nnz = ptr[1]

    cdef CSR_Matrix out
    init_CSR(&out, nnz**2, nrows)

    if is_ket:
        #Compute new ptrs and inds
        for jj in range(nrows):
            out.indptr[jj] = ptr[jj]*nnz
            if ptr[jj+1] != ptr[jj]:
                new_idx = jj
                for kk in range(nnz):
                    out.indices[offset+kk*nnz] = new_idx
                offset += 1
        #set nnz in new ptr
        out.indptr[nrows] = nnz**2

        #Compute the data
        for jj in range(nnz):
            for kk in range(nnz):
                out.data[jj*nnz+kk] = data[jj]*conj(data[kk])

    else:
        # a bra _may_ have unsorted indices (a ket may not in CSR format)
        A.sort_indices()
        count = nnz**2
        new_idx = nrows
        for kk in range(nnz-1,-1,-1):
            for jj in range(nnz-1,-1,-1):
                out.indices[offset+jj] = ind[jj]
                out.data[kk*nnz+jj] = conj(data[kk])*data[jj]
            offset += nnz
            change_idx = ind[kk]
            while new_idx > change_idx:
                out.indptr[new_idx] = count
                new_idx -= 1
            count -= nnz


    return CSR_to_scipy(&out)



@cython.boundscheck(False)
@cython.wraparound(False)
def zcsr_inner(object A, object B, bool bra_ket):
    """
    Computes the inner-product <A|B> between ket-ket,
    or bra-ket vectors in sparse CSR format.
    """
    cdef complex[::1] a_data = A.data
    cdef int[::1] a_ind = A.indices
    cdef int[::1] a_ptr = A.indptr

    cdef complex[::1] b_data = B.data
    cdef int[::1] b_ind = B.indices
    cdef int[::1] b_ptr = B.indptr
    cdef int nrows = B.shape[0]

    cdef double complex inner = 0
    cdef size_t kk
    cdef int a_idx, b_idx

    if bra_ket:
        if A.shape[1] != nrows:
            message = "".join([
                "incompatible lengths ", str(A.shape[1]), " and ", str(nrows),
            ])
            raise TypeError(message)
        for kk in range(a_ind.shape[0]):
            a_idx = a_ind[kk]
            if b_ptr[a_idx + 1] != b_ptr[a_idx]:
                inner += a_data[kk] * b_data[b_ptr[a_idx]]
    else:
        if A.shape[0] != nrows:
            message = "".join([
                "incompatible lengths ", str(A.shape[0]), " and ", str(nrows),
            ])
            raise TypeError(message)
        for kk in range(nrows):
            a_idx = a_ptr[kk]
            b_idx = b_ptr[kk]
            if (a_ptr[kk+1]-a_idx) != 0:
                if (b_ptr[kk+1]-b_idx) != 0:
                    inner += conj(a_data[a_idx])*b_data[b_idx]

    return inner
