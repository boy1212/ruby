##
# A Gem::Security::Policy object encapsulates the settings for verifying
# signed gem files.  This is the base class.  You can either declare an
# instance of this or use one of the preset security policies in
# Gem::Security::Policies.

class Gem::Security::Policy

  attr_reader :name

  attr_accessor :only_signed
  attr_accessor :only_trusted
  attr_accessor :verify_chain
  attr_accessor :verify_data
  attr_accessor :verify_root
  attr_accessor :verify_signer

  ##
  # Create a new Gem::Security::Policy object with the given mode and
  # options.

  def initialize name, policy = {}, opt = {}
    @name = name

    @opt = opt

    # Default to security
    @only_signed   = true
    @only_trusted  = true
    @verify_chain  = true
    @verify_data   = true
    @verify_root   = true
    @verify_signer = true

    policy.each_pair do |key, val|
      case key
      when :verify_data   then @verify_data   = val
      when :verify_signer then @verify_signer = val
      when :verify_chain  then @verify_chain  = val
      when :verify_root   then @verify_root   = val
      when :only_trusted  then @only_trusted  = val
      when :only_signed   then @only_signed   = val
      end
    end
  end

  ##
  # Verifies each certificate in +chain+ has signed the following certificate
  # and is valid for the given +time+.

  def check_chain chain, time
    chain.each_cons 2 do |issuer, cert|
      check_cert cert, issuer, time
    end

    true
  rescue Gem::Security::Exception => e
    raise Gem::Security::Exception, "invalid signing chain: #{e.message}"
  end

  ##
  # Verifies that +data+ matches the +signature+ created by +public_key+ and
  # the +digest+ algorithm.

  def check_data public_key, digest, signature, data
    raise Gem::Security::Exception, "invalid signature" unless
      public_key.verify digest.new, signature, data.digest

    true
  end

  ##
  # Ensures that +signer+ is valid for +time+ and was signed by the +issuer+.
  # If the +issuer+ is +nil+ no verification is performed.

  def check_cert signer, issuer, time
    message = "certificate #{signer.subject}"

    if not_before = signer.not_before and not_before > time then
      raise Gem::Security::Exception,
            "#{message} not valid before #{not_before}"
    end

    if not_after = signer.not_after and not_after < time then
      raise Gem::Security::Exception, "#{message} not valid after #{not_after}"
    end

    if issuer and not signer.verify issuer.public_key then
      raise Gem::Security::Exception,
            "#{message} was not issued by #{issuer.subject}"
    end

    true
  end

  ##
  # Ensures the public key of +key+ matches the public key in +signer+

  def check_key signer, key
    raise Gem::Security::Exception,
      "certificate #{signer.subject} does not match the signing key" unless
        signer.public_key.to_pem == key.public_key.to_pem

    true
  end

  ##
  # Ensures the root certificate in +chain+ is self-signed and valid for
  # +time+.

  def check_root chain, time
    root = chain.first

    raise Gem::Security::Exception,
          "root certificate #{root.subject} is not self-signed " \
          "(issuer #{root.issuer})" if
      root.issuer.to_s != root.subject.to_s # HACK to_s is for ruby 1.8

    check_cert root, root, time
  end

  ##
  # Ensures the root of +chain+ has a trusted certificate in +trust_dir+ and
  # the digests of the two certificates match according to +digester+

  def check_trust chain, digester, trust_dir
    root = chain.first

    path = Gem::Security.trust_dir.cert_path root

    unless File.exist? path then
      message = "root cert #{root.subject} is not trusted"

      message << " (root of signing cert #{chain.last.subject})" if
        chain.length > 1

      raise Gem::Security::Exception, message
    end

    save_cert = OpenSSL::X509::Certificate.new File.read path
    save_dgst = digester.digest save_cert.public_key.to_s

    pkey_str = root.public_key.to_s
    cert_dgst = digester.digest pkey_str

    raise Gem::Security::Exception,
          "trusted root certificate #{root.subject} checksum " \
          "does not match signing root certificate checksum" unless
      save_dgst == cert_dgst

    true
  end

  def inspect # :nodoc:
    "[Policy: %s - data: %p signer: %p chain: %p root: %p " \
      "signed-only: %p trusted-only: %p]" % [
      @name, @verify_chain, @verify_data, @verify_root, @verify_signer,
      @only_signed, @only_trusted,
    ]
  end

  ##
  # Verifies the certificate +chain+ is valid, the +digests+ match the
  # signatures +signatures+ created by the signer depending on the +policy+
  # settings.
  #
  # If +key+ is given it is used to validate the signing certificate.

  def verify chain, key = nil, digests = {}, signatures = {}
    if @only_signed and signatures.empty? then
      raise Gem::Security::Exception,
        "unsigned gems are not allowed by the #{name} policy"
    end

    opt       = @opt
    digester  = Gem::Security::DIGEST_ALGORITHM
    trust_dir = opt[:trust_dir]
    time      = Time.now

    signer_digests = digests.find do |algorithm, file_digests|
      file_digests.values.first.name == Gem::Security::DIGEST_NAME
    end

    signer_digests = digests.values.first || {}

    signer = chain.last

    check_key signer, key if key

    check_cert signer, nil, time if @verify_signer

    check_chain chain, time if @verify_chain

    check_root chain, time if @verify_root

    check_trust chain, digester, trust_dir if @only_trusted

    signer_digests.each do |file, digest|
      signature = signatures[file]

      raise Gem::Security::Exception, "missing signature for #{file}" unless
        signature

      check_data signer.public_key, digester, signature, digest if @verify_data
    end

    true
  end

  ##
  # Extracts the certificate chain from the +spec+ and calls #verify to ensure
  # the signatures and certificate chain is valid according to the policy..

  def verify_signatures spec, digests, signatures
    chain = spec.cert_chain.map do |cert_pem|
      OpenSSL::X509::Certificate.new cert_pem
    end

    verify chain, nil, digests, signatures

    true
  end

  alias to_s name # :nodoc:

end

