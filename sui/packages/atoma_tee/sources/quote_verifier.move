module atoma_tee::quote_verifier {

    use atoma_tee::types::{Header, EnclaveReport, create_enclave_report};

    /// Length of the enclave report
    const ENCLAVE_REPORT_LENGTH: u16 = 384;

    /// Supported attestation key type
    const SUPPORTED_ATTESTATION_KEY_TYPE: u16 = 0x0200; // ECDSA_256_WITH_P256_CURVE (LE)

    /// Valid QE vendor ID
    const VALID_QE_VENDOR_ID: vector<u8> = x"939a7233f79c4ca9940a0db3957f0607";

    /// SGX TEE type
    const SGX_TEE: u8 = 0x00000000;

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
    const EInvalidSignature: u64 = 1;
    const EInvalidTCB: u64 = 2;
    const EInvalidQuoteLength: u64 = 3;
    const EInvalidTEEType: u64 = 4;
    const EInvalidAttestationKeyType: u64 = 5;
    const EInvalidQEVendorID: u64 = 6;
    const EInvalidReportLength: u64 = 7;
    const EInvalidVectorLength: u64 = 8;

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
        quote_length: u16,
        expected_quote_version: u16,
        tee_is_valid: bool,
    ) { 
        // Check minimum quote length
        assert!(quote_length >= MINIMUM_QUOTE_LENGTH, EInvalidQuoteLength);
        
        // Check quote version
        assert!(header.get_header_version() == expected_quote_version, EInvalidQuoteVersion);

        // Check attestation key type
        assert!(header.get_attestation_key_type() == SUPPORTED_ATTESTATION_KEY_TYPE, EInvalidAttestationKeyType);

        // Check TEE type validity
        assert!(tee_is_valid, EInvalidTEEType);

        // Check QE vendor ID
        assert!(header.get_qe_vendor_id() == VALID_QE_VENDOR_ID, EInvalidQEVendorID);
    }

    /// Parses a raw enclave report into a structured EnclaveReport object
    /// 
    /// # Arguments
    /// * `raw_enclave_report` - Vector of bytes containing the raw enclave report
    /// 
    /// # Returns
    /// * `EnclaveReport` - Structured enclave report data
    /// 
    /// # Aborts
    /// * `EInvalidReportLength` - If the input length doesn't match ENCLAVE_REPORT_LENGTH
    /// * `EInvalidVectorLength` - If any substring operation fails
    public fun parse_enclave_report(raw_enclave_report: vector<u8>): EnclaveReport { 
        // Verify total length
        assert!(vector::length(&raw_enclave_report) == ENCLAVE_REPORT_LENGTH as u64, EInvalidReportLength);

        let cpu_svn = extract_bytes(raw_enclave_report, 0, 16);
        let misc_select = extract_bytes(raw_enclave_report, 16, 4);
        let reserved1 = extract_bytes(raw_enclave_report, 20, 28);
        let attributes = extract_bytes(raw_enclave_report, 48, 16);
        let mr_enclave = extract_bytes(raw_enclave_report, 64, 32);
        let reserved2 = extract_bytes(raw_enclave_report, 96, 32);
        let mr_signer = extract_bytes(raw_enclave_report, 128, 32);
        let reserved3 = extract_bytes(raw_enclave_report, 160, 96);
        let isv_prod_id = bytes_to_u16(extract_bytes(raw_enclave_report, 256, 2));
        let isv_svn = bytes_to_u16(extract_bytes(raw_enclave_report, 258, 2));
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

    /// Extracts a subset of bytes from a vector starting at a specified position
    /// 
    /// # Arguments
    /// * `raw_enclave_report` - Source vector of bytes to extract from
    /// * `start` - Starting index position in the source vector
    /// * `len` - Number of bytes to extract
    /// 
    /// # Returns
    /// * `vector<u8>` - New vector containing the extracted bytes
    /// 
    /// # Example
    /// ```
    /// let data = vector[1, 2, 3, 4, 5];
    /// let subset = extract_bytes(data, 1, 2); // Returns vector[2, 3]
    /// ```
    fun extract_bytes(raw_enclave_report: vector<u8>, start: u64, len: u64): vector<u8> { 
        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < len) { 
            vector::push_back(&mut result, *vector::borrow(&raw_enclave_report, start + i));
            i = i + 1;
        };
        result
    }

    /// Converts a 2-byte vector into a u16 value using little-endian byte order
    /// 
    /// # Arguments
    /// * `bytes` - Vector containing exactly 2 bytes in little-endian order
    /// 
    /// # Returns
    /// * `u16` - The converted 16-bit unsigned integer
    /// 
    /// # Aborts
    /// * `EInvalidVectorLength` - If the input vector does not contain exactly 2 bytes
    /// 
    /// # Example
    /// ```
    /// let bytes = vector[0x34, 0x12];  // 0x1234 in little-endian
    /// let value = bytes_to_u16(bytes); // Returns 0x1234 (4660 in decimal)
    /// ```
    fun bytes_to_u16(bytes: vector<u8>): u16 { 
        assert!(vector::length(&bytes) == 2, EInvalidVectorLength);
        (((*vector::borrow(&bytes, 1) as u16) << 8) | (*vector::borrow(&bytes, 0) as u16))
    }
}