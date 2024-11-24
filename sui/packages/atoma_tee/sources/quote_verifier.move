module atoma_tee::quote_verifier {

    use atoma_tee::types::{
        Header,
        EcdsaQuoteV4AuthData,
        EnclaveReport,
        TD10ReportBody,
        V4TDXQuote,
        create_enclave_report,
        create_td10_report_body,
        create_ecdsa_quote_v4_auth_data,
        create_qe_report_cert_data,
        create_pck_collateral,
        create_pck_cert_tcb,
        create_qe_auth_data,
        create_certification_data,
        create_v4_tdx_quote,
        get_quote_auth_data,
        get_quote_tee_type,
        get_qe_data_from_auth,
        get_attestation_key_from_auth,
        get_qe_auth_data,
        get_quote_report_body_tee_tcb_svn,
        get_quote_report_body_mrsigner_seam,
        get_quote_report_body_seam_attributes,
        get_pck_chain,
        get_pck_extension,
        get_qe_report,
    };
    use atoma_tee::utils::{
        extract_bytes,
        le_bytes_to_u16,
        le_bytes_to_u32,
        le_bytes_to_u64,
        le_bytes_to_u128,
        le_bytes_to_u256,
        int_to_le_bytes,
        compare_vectors,
    };
    use std::hash::sha2_256;
    use sui::ecdsa_r1;

    /// Hash function name for SHA256, following the convention in
    /// Reference: https://docs.sui.io/references/framework/sui-framework/ecdsa_r1
    const SHA256_HASH_U8_IDENTIFIER: u8 = 1;

    /// Length of the enclave report
    const ENCLAVE_REPORT_LENGTH: u16 = 384;

    /// Supported attestation key type
    const SUPPORTED_ATTESTATION_KEY_TYPE: u16 = 0x0200; // ECDSA_256_WITH_P256_CURVE (LE)

    /// Valid QE vendor ID
    const VALID_QE_VENDOR_ID: u128 = 0x939a7233f79c4ca9940a0db3957f0607;

    /// Length of the QE report data
    const QE_REPORT_DATA_LENGTH: u64 = 32;

    /// Length of the quote header
    const HEADER_LENGTH: u64 = 48;

    /// Length of the TD10 report body
    const TD_REPORT10_LENGTH: u64 = 584;

    /// Expected quote version
    /// Reference: https://download.01.org/intel-sgx/latest/dcap-latest/linux/docs/Intel_TDX_DCAP_Quoting_Library_API.pdf
    /// 
    /// TODO: This is currently a static value, but it should be able to be updated over time by the Atoma TEE contract admin
    const EXPECTED_QUOTE_VERSION: u16 = 0x0004;

    /// Lengths of the TD10 report body fields

    /// Length of the TEE TCB SVN field
    const TEE_TCB_SVN_LENGTH: u64 = 16;
    /// Length of the MR fields
    const MR_LENGTH: u64 = 48;
    /// Length of the attributes fields
    const ATTRIBUTES_LENGTH: u64 = 8;
    /// Length of the report data
    const REPORT_DATA_LENGTH: u64 = 64;

    /// TDX TEE type
    const TDX_TEE: u8 = 0x00000081;

    /// Minimum output length for the remote attestation quote
    /// QUOTE_VERSION (2 bytes) + TEE_TYPE (4 bytes) + TCB_STATUS (1 byte) + FMSPC (6 bytes)
    const MINIMUM_OUTPUT_LENGTH: u16 = 13;

    /// Minimum quote length for the remote attestation quote   
    /// Header (48 bytes) + Body (minimum 384 bytes) + AuthDataSize (4 bytes) + AuthData:
    /// ECDSA_SIGNATURE (64 bytes) + ECDSA_KEY (64 bytes) + QE_REPORT_BYTES (384 bytes)
    /// + QE_REPORT_SIGNATURE (64 bytes) + QE_AUTH_DATA_SIZE (2 bytes) + QE_CERT_DATA_TYPE (2 bytes)
    /// + QE_CERT_DATA_SIZE (4 bytes)
    const MINIMUM_QUOTE_LENGTH: u16 = 1020;

    /// Error codes
    const EInvalidQuoteVersion: u64 = 0;
    const EInvalidQuoteLength: u64 = 1;
    const EInvalidTEEType: u64 = 2;
    const EInvalidAttestationKeyType: u64 = 3;
    const EInvalidQEVendorID: u64 = 4;
    const EInvalidReportLength: u64 = 5;
    const EInvalidReportDataLength: u64 = 6;
    const EInvalidCertificationType: u64 = 7;
    const EInvalidQETcbStatus: u64 = 8;
    const ETcbNotFoundOrExpired: u64 = 9;

    /// Verifies an intel TDX remote attestation quote by parsing and validating its components
    /// 
    /// NOTE: We currently only support intel TDX quote verification
    /// 
    /// # Arguments
    /// * `header` - Reference to the quote header containing metadata
    /// * `raw_quote` - Raw bytes of the complete quote
    /// 
    /// # Flow
    /// 1. Parses the quote into its constituent parts (body, QE report, auth data)
    /// 2. Extracts raw header and determines TEE type
    /// 3. For TDX quotes:
    ///    - Parses the TD report body
    ///    - Creates a structured quote object
    ///    - Performs detailed verification via verify_tdx_quote
    /// 
    /// # Aborts
    /// * `EInvalidTEEType` - If the quote is not from a TDX TEE
    /// * May also abort with other error codes from called functions
    public fun verify_quote(header: &Header, raw_quote: vector<u8>) {
        // Parse the quote into its body, QE report, and authentication data
        let (raw_quote_body, raw_qe_report, auth_data) = parse_v4_quote(header, raw_quote);

        // Get raw header and body on TEE type
        let raw_header = extract_bytes(raw_quote, 0, HEADER_LENGTH);
        let tee_type = header.get_tee_type();

        if (tee_type == TDX_TEE as u32) {
            let td_report = parse_td10_report_body(raw_quote_body);
            let raw_body = extract_bytes(raw_quote, HEADER_LENGTH, TD_REPORT10_LENGTH);
            let quote = create_v4_tdx_quote(header, td_report, auth_data);
            verify_tdx_quote(&quote, raw_header, raw_body, raw_qe_report);
        }
        else { 
            abort EInvalidTEEType
        }
    }

    fun verify_tdx_quote(
        quote: &V4TDXQuote,
        raw_header: vector<u8>,
        raw_body: vector<u8>,
        raw_qe_report: vector<u8>,
    ) {
        // 1. Verification steps that are required for TDX quotes (it should also work for SGX quotes, in the future)
        verify_common(
            get_quote_tee_type(quote), 
            raw_header, 
            raw_body, 
            &get_quote_auth_data(quote)
        );

        // // 2. Get the TCB Status from the TDXComponent of the matching TCBLevel
        // get_tdx_tcb_status();

        // // 3. Fetch TDXModule TCB Status
        // let (
        //     tdx_module_version, 
        //     expected_mr_signer_seam, 
        //     expected_seam_attributes
        // ) = check_tdx_module_tcb_status(
        //     get_quote_report_body_tee_tcb_svn(quote), 
        //     // TODO: add ret tdx module identities 
        // );

        // // 4. Check TDX modules
        // check_tdx_module(
        //     get_quote_report_body_mrsigner_seam(quote),
        //     get_quote_report_body_seam_attributes(quote),
        //     expected_seam_attributes,
        // );
    }

    fun verify_common(
        tee_type: u32,
        raw_header: vector<u8>,
        raw_body: vector<u8>,
        auth_data: &EcdsaQuoteV4AuthData
    ) {
        // Step 0: Verify QE report data
        verify_qe_report_data(
            get_qe_data_from_auth(auth_data), 
            get_attestation_key_from_auth(auth_data), 
            get_qe_auth_data(auth_data)
        );

        // // Step 1: Fetch QE Identity and validate TCB of the QE
        // let qe_report = get_qe_report(auth_data);
        // fetch_qe_identity_and_check_qe_report(tee_type, qe_report);
        // assert!(qe_tcb_status != EnclaveIdTcbStatus::SGX_ENCLAVE_REPORT_ISVSVN_REVOKED, EInvalidQETcbStatus);


        // // Step 2: Fetch FMSPC TCB
        // let pck_chain = get_pck_chain(auth_data);
        // let pck_tcb = get_pck_extension(auth_data);
        // let (tcb_levels, tdx_module, tdx_module_identities) = get_fmspc_tcb_v3(
        //     tee_type,
        //     pck_tcb.fmspc_bytes
        // );
        // assert!(!vector::is_empty(&tcb_levels), ETcbNotFoundOrExpired);

        // // Step 3: Verify certificate chain
        // let cert_chain_verified = verify_cert_chain(pck_chain);
        // assert!(cert_chain_verified, EFailedCertChainVerification);

        // // Step 4: Verify signatures
        // // Concatenate raw_header and raw_body for local attestation data
        // let mut local_attestation_data = vector::empty<u8>();
        // vector::append(&mut local_attestation_data, raw_header);
        // vector::append(&mut local_attestation_data, raw_body);

        // // Get PCK public key from first certificate in chain
        // let pck_pubkey = get_subject_public_key(&vector::borrow(pck_chain, 0));

        // let signatures_verified = attestation_verification(
        //     auth_data.qe_report_cert_data.qe_report,
        //     auth_data.qe_report_cert_data.qe_report_signature,
        //     pck_pubkey,
        //     local_attestation_data,
        //     auth_data.ecdsa_signature,
        //     auth_data.ecdsa_attestation_key
        // );
        // assert!(signatures_verified, EFailedSignatureVerification);
    }

    /// Parses a v4 TDX quote into its constituent parts
    /// 
    /// # Arguments
    /// * `header` - Reference to the quote header containing metadata
    /// * `raw_quote` - Raw bytes of the complete quote
    /// 
    /// # Returns
    /// * `(vector<u8>, vector<u8>, EcdsaQuoteV4AuthData)` - A tuple containing:
    ///   - Raw quote body bytes
    ///   - Raw QE report bytes
    ///   - Parsed authentication data structure
    /// 
    /// # Data Structure
    /// The quote consists of:
    /// - Header (48 bytes)
    /// - TD Report Body (584 bytes)
    /// - Auth Data Size (4 bytes)
    /// - Auth Data (variable length):
    ///   - ECDSA signature
    ///   - Attestation key
    ///   - QE report certification data
    /// 
    /// # Aborts
    /// * `EInvalidTEEType` - If quote is not from a TDX TEE
    /// * `EInvalidQuoteLength` - If auth data size exceeds remaining quote length
    fun parse_v4_quote(header: &Header, raw_quote: vector<u8>): (vector<u8>, vector<u8>, EcdsaQuoteV4AuthData) {
        let tee_type = header.get_tee_type();
        assert!(tee_type == TDX_TEE as u32, EInvalidTEEType);
        validate_header(header, raw_quote.length());
        
        let mut offset = HEADER_LENGTH + TD_REPORT10_LENGTH;
        let raw_quote_body = extract_bytes(raw_quote, HEADER_LENGTH, offset);

        // Check the auth data length
        let local_auth_data_size = le_bytes_to_u32(extract_bytes(raw_quote_body, offset, 4));
        offset = offset + 4;
        if (raw_quote.length() - offset < local_auth_data_size as u64) {
            abort EInvalidQuoteLength
        };

        // We have validated the quote length, so we can safely extract the auth data
        let (auth_data, raw_qe_report) = parse_auth_data(extract_bytes(raw_quote, offset, local_auth_data_size as u64));
        (raw_quote_body, raw_qe_report, auth_data)
    }

    /// Parses the authentication data section of a TDX quote into structured data
    /// 
    /// # Arguments
    /// * `raw_auth_data` - Raw bytes containing the authentication data section of the quote
    /// 
    /// # Returns
    /// * `(EcdsaQuoteV4AuthData, vector<u8>)` - A tuple containing:
    ///   - Parsed authentication data structure
    ///   - Raw QE report bytes (needed for signature verification)
    /// 
    /// # Data Structure
    /// The authentication data section contains:
    /// - ECDSA Signature (64 bytes)
    /// - ECDSA Attestation Public Key (64 bytes)
    /// - QE Report Certification Data:
    ///   - Type (2 bytes, must be value 6)
    ///   - Size (4 bytes)
    ///   - QE Report (384 bytes)
    ///   - QE Report Signature (64 bytes)
    ///   - QE Authentication Data:
    ///     - Size (2 bytes)
    ///     - Data (variable length)
    ///   - Certification Data:
    ///     - Type (2 bytes, must be value 5)
    ///     - Size (4 bytes)
    ///     - Data (variable length, contains PCK collateral)
    /// 
    /// # Aborts
    /// * `EInvalidCertificationType` - If QE report cert type != 6 or cert type != 5
    /// * `EInvalidReportLength` - If the total parsed size doesn't match qe_report_cert_size
    fun parse_auth_data(raw_auth_data: vector<u8>): (EcdsaQuoteV4AuthData, vector<u8>) {
        // Extract initial fields
        let ecdsa_signature = extract_bytes(raw_auth_data, 0, 64);
        let ecdsa_attestation_key = extract_bytes(raw_auth_data, 64, 64);

        // Verify QE report cert type (must be 6)
        let qe_report_cert_type = le_bytes_to_u16(extract_bytes(raw_auth_data, 128, 2));
        if (qe_report_cert_type != 6) { 
            abort EInvalidCertificationType
        };

        // Get QE report cert size
        let qe_report_cert_size = le_bytes_to_u32(extract_bytes(raw_auth_data, 130, 4));

        // Extract QE report and signature
        let raw_qe_report = extract_bytes(raw_auth_data, 134, 384);
        let qe_report_signature = extract_bytes(raw_auth_data, 518, 64);

        // Get QE auth data size and extract auth data
        let qe_auth_data_size = le_bytes_to_u16(extract_bytes(raw_auth_data, 582, 2));
        let mut offset = 584;
        let qe_auth_data = extract_bytes(raw_auth_data, offset, qe_auth_data_size as u64);
        offset = offset + (qe_auth_data_size as u64);

        // Extract and verify cert type (must be 5)
        let cert_type = le_bytes_to_u16(extract_bytes(raw_auth_data, offset, 2));
        if (cert_type != 5) {
            abort EInvalidCertificationType
        };
        offset = offset + 2;

        // Get cert data size and extract cert data
        let cert_data_size = le_bytes_to_u32(extract_bytes(raw_auth_data, offset, 4));
        offset = offset + 4;
        // NOTE: `raw_cert_data` is to be used for getting PCK collateral
        let raw_cert_data = extract_bytes(raw_auth_data, offset, cert_data_size as u64);
        offset = offset + (cert_data_size as u64);

        // Verify total size matches qe_report_cert_size
        assert!(offset - 134 == qe_report_cert_size as u64, EInvalidReportLength);

        // Parse QE report
        let qe_report = parse_enclave_report(raw_qe_report);

        // Create QE auth data struct
        let qe_auth_data = create_qe_auth_data(
            qe_auth_data_size,
            qe_auth_data
        );

        // Create certification data struct
        let certification = create_certification_data(
            cert_type,
            cert_data_size,
            // TODO: We need to implement PCK collateral parsing similar to the Solidity getPckCollateral
            create_pck_collateral(vector::empty(), create_pck_cert_tcb(0, vector::empty(), vector::empty(), vector::empty()))
        );

        // Create QE report cert data struct
        let qe_report_cert_data = create_qe_report_cert_data(
            qe_report,
            qe_report_signature,
            qe_auth_data,
            certification
        );

        // Create final auth data struct
        let auth_data = create_ecdsa_quote_v4_auth_data(
            ecdsa_signature,
            ecdsa_attestation_key,
            qe_report_cert_data
        );

        (auth_data, raw_qe_report)
    }

    /// Parses a raw byte array into a TD10ReportBody structure
    /// 
    /// # Arguments
    /// * `report_bytes` - Raw bytes containing the TD10 report body
    /// 
    /// # Returns
    /// * `TD10ReportBody` - Parsed TDX report body structure
    /// 
    /// # Aborts
    /// * `EInvalidReportLength` - If input length is invalid
    /// * `EInvalidOffset` - If any field offset is invalid
    public fun parse_td10_report_body(report_bytes: vector<u8>): TD10ReportBody {
        // Expected total length is 584 bytes (520 + 64)
        let total_length = 584u64;
        assert!(vector::length(&report_bytes) == total_length, EInvalidReportLength);

        // Extract all fields
        let tee_tcb_svn = extract_bytes(report_bytes, 0, TEE_TCB_SVN_LENGTH);
        let mr_seam = extract_bytes(report_bytes, 16, MR_LENGTH);
        let mrsigner_seam = extract_bytes(report_bytes, 64, MR_LENGTH);
        
        // Convert LE bytes to u64 for attributes
        let seam_attributes = extract_bytes(report_bytes, 112, ATTRIBUTES_LENGTH);
        let seam_attributes_int = le_bytes_to_u64(seam_attributes);
        let seam_attributes = int_to_le_bytes(seam_attributes_int);

        let td_attributes = extract_bytes(report_bytes, 120, ATTRIBUTES_LENGTH);
        let td_attributes_int = le_bytes_to_u64(td_attributes);
        let td_attributes = int_to_le_bytes(td_attributes_int);

        let xfam = extract_bytes(report_bytes, 128, ATTRIBUTES_LENGTH);
        let xfam_int = le_bytes_to_u64(xfam);
        let xfam = int_to_le_bytes(xfam_int);

        let mr_td = extract_bytes(report_bytes, 136, MR_LENGTH);
        let mr_config_id = extract_bytes(report_bytes, 184, MR_LENGTH);
        let mr_owner = extract_bytes(report_bytes, 232, MR_LENGTH);
        let mr_owner_config = extract_bytes(report_bytes, 280, MR_LENGTH);
        let rt_mr0 = extract_bytes(report_bytes, 328, MR_LENGTH);
        let rt_mr1 = extract_bytes(report_bytes, 376, MR_LENGTH);
        let rt_mr2 = extract_bytes(report_bytes, 424, MR_LENGTH);
        let rt_mr3 = extract_bytes(report_bytes, 472, MR_LENGTH);
        let report_data = extract_bytes(report_bytes, 520, REPORT_DATA_LENGTH);

        create_td10_report_body(
            tee_tcb_svn,
            mr_seam,
            mrsigner_seam,
            seam_attributes,
            td_attributes,
            xfam,
            mr_td,
            mr_config_id,
            mr_owner,
            mr_owner_config,
            rt_mr0,
            rt_mr1,
            rt_mr2,
            rt_mr3,
            report_data,
        )
    }

    /// Validates the header of a remote attestation quote against expected values and constraints.
    /// 
    /// # Arguments
    /// * `header` - Reference to the Header struct containing quote metadata
    /// * `quote_length` - Total length of the quote in bytes
    /// * `expected_quote_version` - Expected version number of the quote
    /// * `tee_is_valid` - Boolean indicating if the TEE type is valid (SGX or TDX)
    /// 
    /// # Returns
    /// * `bool` - Returns true if all validations pass
    /// 
    /// # Aborts
    /// * `EInvalidQuoteLength` - If quote length is less than minimum required (1020 bytes)
    /// * `EInvalidQuoteVersion` - If quote version doesn't match expected version
    /// * `EInvalidAttestationKeyType` - If attestation key type is not ECDSA_256_WITH_P256_CURVE
    /// * `EInvalidTEEType` - If TEE type is neither SGX nor TDX
    /// * `EInvalidQEVendorID` - If QE vendor ID doesn't match the valid ID
    public fun validate_header(
        header: &Header,
        quote_length: u64,
    ) { 
        // Check minimum quote length
        assert!(quote_length >= MINIMUM_QUOTE_LENGTH as u64, EInvalidQuoteLength);
        
        // Check quote version
        assert!(header.get_header_version() == EXPECTED_QUOTE_VERSION, EInvalidQuoteVersion);

        // Check attestation key type
        assert!(header.get_attestation_key_type() == SUPPORTED_ATTESTATION_KEY_TYPE, EInvalidAttestationKeyType);

        // Check QE vendor ID
        assert!(header.get_qe_vendor_id() == VALID_QE_VENDOR_ID, EInvalidQEVendorID);
    }

    /// Parses a raw enclave report into a eport object
    /// 
    /// # Arguments
    /// * `raw_enclave_report` - Vector of bytes containing the raw enclave report
    /// 
    /// # Returns
    /// * eport` - Structured enclave report data
    /// 
    /// # Aborts
    /// * `EInvalidReportLength` - If the input length doesn't match ENCLAVE_REPORT_LENGTH
    /// * `EInvalidVectorLength` - If any substring operation fails
    public fun parse_enclave_report(raw_enclave_report: vector<u8>): EnclaveReport { 
        // Verify total length
        assert!(vector::length(&raw_enclave_report) == ENCLAVE_REPORT_LENGTH as u64, EInvalidReportLength);

        let cpu_svn = le_bytes_to_u128(extract_bytes(raw_enclave_report, 0, 16));
        let misc_select = le_bytes_to_u32(extract_bytes(raw_enclave_report, 16, 4));
        let reserved1 = extract_bytes(raw_enclave_report, 20, 28);
        let attributes = le_bytes_to_u128(extract_bytes(raw_enclave_report, 48, 16));
        let mr_enclave = le_bytes_to_u256(extract_bytes(raw_enclave_report, 64, 32));
        let reserved2 = le_bytes_to_u256(extract_bytes(raw_enclave_report, 96, 32));
        let mr_signer = le_bytes_to_u256(extract_bytes(raw_enclave_report, 128, 32));
        let reserved3 = extract_bytes(raw_enclave_report, 160, 96);
        let isv_prod_id = le_bytes_to_u16(extract_bytes(raw_enclave_report, 256, 2));
        let isv_svn = le_bytes_to_u16(extract_bytes(raw_enclave_report, 258, 2));
        let reserved4 = extract_bytes(raw_enclave_report, 260, 60);
        let report_data = extract_bytes(raw_enclave_report, 320, 64);

        create_enclave_report(
            cpu_svn,
            misc_select,
            reserved1,
            attributes,
            mr_enclave,
            reserved2,
            mr_signer,
            reserved3,
            isv_prod_id,
            isv_svn,
            reserved4,
            report_data
        )
    }

    /// Verifies QE report data by comparing it with the hash of attestation key and QE auth data
    /// 
    /// # Arguments
    /// * `qe_report_data` - Expected hash value from the QE report (32 bytes)
    /// * `attestation_key` - Attestation key bytes to be included in hash preimage
    /// * `qe_auth_data` - QE authentication data to be included in hash preimage
    /// 
    /// # Returns
    /// * `bool` - True if verification succeeds, false otherwise
    /// 
    /// # Aborts
    /// * `EInvalidReportDataLength` - If qe_report_data is not 32 bytes
    public fun verify_qe_report_data(
        qe_report_data: vector<u8>,
        attestation_key: vector<u8>,
        qe_auth_data: vector<u8>
    ): bool {
        // Verify qe_report_data length is 32 bytes (256 bits)
        assert!(
            vector::length(&qe_report_data) == QE_REPORT_DATA_LENGTH, 
            EInvalidReportDataLength
        );

        // Create preimage by concatenating attestation_key and qe_auth_data
        let mut preimage = vector::empty<u8>();
        vector::append(&mut preimage, attestation_key);
        vector::append(&mut preimage, qe_auth_data);

        // Compute SHA256 hash
        let computed_hash = sha2_256(preimage);

        // Compare computed hash with expected hash (qe_report_data)
        compare_vectors(&computed_hash, &qe_report_data)
    }

    /// Verifies both QE report and attestation signatures using ECDSA with P256 curve
    /// 
    /// # Arguments
    /// * `raw_qe_report` - Raw QE report bytes to verify
    /// * `qe_signature` - Signature of the QE report
    /// * `pck_pubkey` - Public key for QE report verification
    /// * `signed_attestation_data` - Attestation data to verify
    /// * `attestation_signature` - Signature of the attestation data
    /// * `attestation_key` - Public key for attestation verification
    /// 
    /// # Returns
    /// * `bool` - True if both verifications succeed, false otherwise
    /// 
    /// # Aborts
    /// * `EInvalidSignatureLength` - If signature length is invalid
    /// * `EInvalidKeyLength` - If public key length is invalid
    public fun attestation_verification(
        raw_qe_report: vector<u8>,
        qe_signature: vector<u8>,
        pck_pubkey: vector<u8>,
        signed_attestation_data: vector<u8>,
        attestation_signature: vector<u8>,
        attestation_key: vector<u8>
    ): bool {
        // First verify QE report
        let qe_report_hash = sha2_256(raw_qe_report);
        
        let qe_report_verified = ecdsa_r1::secp256r1_verify(
            &qe_signature,
            &pck_pubkey,
            &qe_report_hash,
            SHA256_HASH_U8_IDENTIFIER,
        );

        // Early return if QE report verification fails
        if (!qe_report_verified) {
            return false
        };

        // Then verify attestation data
        let attestation_hash = sha2_256(signed_attestation_data);
        
        let attestation_verified = ecdsa_r1::secp256r1_verify(
            &attestation_signature,
            &attestation_key,
            &attestation_hash,
            SHA256_HASH_U8_IDENTIFIER,
        );

        attestation_verified
    }
}