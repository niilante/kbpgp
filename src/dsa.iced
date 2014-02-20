bn = require './bn'
{nbv,BigInteger} = bn
{SRF,MRF} = require './rand'
{bufeq_secure,ASP} = require './util'
{make_esc} = require 'iced-error'
konst = require './const'
C = konst.openpgp
K = konst.kb

#=================================================================

class Priv

  #----------------

  constructor : ( {@x,@pub} ) ->

  #----------------

  serialize : () -> @x.to_mpi_buffer()

  #----------------

  @alloc : (raw, pub) ->
    orig = raw.length
    [ err, x, raw ] = bn.mpi_from_buffer raw
    if err? then [err, null]
    else [ null, new Priv { x, pub}, (orig - raw.length) ]

  #----------------

  sign : (h, cb) ->
    hi = bn.bn_from_left_n_bits h, q.bitLength()
    await SRF().random_zn @q.subtract(nbv(2)), defer k
    k = k.add BigInteger.ONE
    r = @g.modPow(k, @p).mod(@q)
    s = (k.modInverse(@q).multiply(hi.add(@x.multiply(r)))).mod(@q)
    cb [r,s]

#=================================================================

class Pub

  @type : C.public_key_algorithms.DSA
  type : Pub.type

  #----------------

  # The serialization order of the parameters in the public key
  @ORDER : [ 'p', 'q', 'g', 'y' ]
  ORDER : Pub.ORDER

  #----------------

  constructor : ({@p, @q, @g, @y}) ->

  #----------------

  serialize : () -> 
    Buffer.concat( @[e].to_mpi_buffer() for e in @ORDER )

  #----------------

  @alloc : (raw) ->
    orig_len = raw.length
    d = {}
    err = null
    for o in Pub.ORDER when not err?
      [err, d[o], raw ] = bn.mpi_from_buffer raw
    if err then [ err, null ]
    else [ null, new Pub(d), (orig_len - raw.length) ]

  #----------------

  verify : ([r, s], h, cb) ->
    err = null
    hi = bn.bn_from_left_n_bits h, @q.bitLength()
    w = s.modInverse @q
    u1 = hi.multiply(w).mod(@q)
    u2 = r.multiply(w).mod(@q)
    v = @g.modPow(u1, @p).multiply(@y.modPow(u2, @p)).mod(@p).mod(@q)
    err = new Error "hash mismatch" if not v.equals(r)
    cb err

#=================================================================

class Pair

  #--------------------

  @type : C.public_key_algorithms.DSA
  type : Pair.type

  #--------------------
  
  constructor : ({ @pub, @priv }) ->

  #--------------------
  
  @parse : (pub_raw) -> 
    [err, key, len] = Pub.alloc pub_raw
    key = new Pair { pub : key } if key?
    [err, key, len ]

  #----------------

  serialize : () -> @pub.serialize()

  #----------------


  pad_and_sign : (data, {hasher}, cb) ->
    # XXX use the DSA recommendations for which hash to use
    hasher or= SHA512
    hashed_data = hasher data
    await @sign hashed_data, defer [r,s]
    out = Buffer.concat [ r.to_mpi_buffer(), s.to_mpi_buffer() ]
    cb out
    
  #----------------

  verify_unpad_and_check_hash : (sig, data, hasher, cb) ->
    err = null
    [err, sig] = Pair.read_sig_from_buf(sig) if Buffer.isBuffer(sig)
    hash = hasher data
    if sig.length isnt 2
      err = new Error "Expected 2 Bigints in the signature"
    else
      await @pub.verify sig, hash, defer err, v
    cb err

  #----------------

  # Parse a signature out of a packet
  #
  # @param {SlicerBuffer} slice The input slice
  # @return {BigInteger} the Signature
  # @throw {Error} an Error if there was an overrun of the packet.
  @parse_sig : (slice) -> 
    buf = slice.peek_rest_to_buffer()
    [err, ret, n] = @read_sig_from_buf buf
    throw err if err?
    slice.advance n
    return ret

  #----------------

  #
  # Read the signature out of a buffer
  #
  # @param {Buffer} the buffer to examine
  # @return {Array<Error,Array<BigInteger,BigInteger>,n} a triple, consisting
  #  of an error (if one happened); the signature (a tuple of BigIntegers meaning 'r' and 's'),
  #  and finally the number of bytes consumed.
  # 
  @read_sig_from_buf : (buf) ->
    orig_len = buf.length
    order = [ 'r', 's' ]
    err = null
    ret = for o in order when not err?
      [err, x, buf] = bn.mpi_from_buffer buf
      x
    n = orig_len - buf.length
    return [err, ret, n]

  #----------------

#=================================================================

exports.DSA = exports.Pair = Pair

#=================================================================
