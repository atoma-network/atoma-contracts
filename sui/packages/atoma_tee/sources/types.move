module atoma_tee::types {

    /// The length of the TCB SVN in bytes
    const TEE_TCB_SVN_LENGTH: u64 = 16;
    /// The length of the MR in bytes
    const MR_LENGTH: u64 = 48;
    /// The length of the attributes in bytes
    const ATTRIBUTES_LENGTH: u64 = 8;
    /// The length of the report data in bytes
    const REPORT_DATA_LENGTH: u64 = 64;
    /// The length of the signature in bytes
    const SIGNATURE_LENGTH: u64 = 64;

    /// Error code for invalid byte buffer length
    const EInvalidLength: u64 = 0;

    /// Represents the TD 1.0 Report Body structure that contains measurements and attributes
    /// of a Trust Domain (TD) environment.
    /// 
    /// This structure is a key component of TDX (Trust Domain Extensions) attestation,
    /// containing various measurements and configuration data that define the TD's identity
    /// and security state.
    ///
    /// Reference: https://github.com/intel/SGX-TDX-DCAP-QuoteVerificationLibrary/blob/7e5b2a13ca5472de8d97dd7d7024c2ea5af9a6ba/Src/AttestationLibrary/src/QuoteVerification/QuoteStructures.h#L82-L103
    public struct TD10ReportBody has store, copy, drop {
        /// TCB (Trusted Computing Base) Security Version Numbers for the TEE
        tee_tcb_svn: vector<u8>,      // 16 bytes
        /// Measurement Register for SEAM (Secure Arbitration Mode) module
        mr_seam: vector<u8>,          // 48 bytes
        /// Measurement of the entity that signed the SEAM module
        mrsigner_seam: vector<u8>,    // 48 bytes
        /// Security attributes of the SEAM module
        seam_attributes: vector<u8>,   // 8 bytes
        /// Security attributes of the Trust Domain
        td_attributes: vector<u8>,     // 8 bytes
        /// Extended Feature Activation Mask - defines enabled CPU features
        xfam: vector<u8>,             // 8 bytes
        /// Measurement Register for the Trust Domain
        mr_td: vector<u8>,            // 48 bytes
        /// Measurement of the TD's configuration ID
        mr_config_id: vector<u8>,     // 48 bytes
        /// Measurement of the TD owner's identity
        mr_owner: vector<u8>,         // 48 bytes
        /// Measurement of the TD owner's configuration
        mr_owner_config: vector<u8>,  // 48 bytes
        /// Runtime Measurement Register 0
        rt_mr0: vector<u8>,           // 48 bytes
        /// Runtime Measurement Register 1
        rt_mr1: vector<u8>,           // 48 bytes
        /// Runtime Measurement Register 2
        rt_mr2: vector<u8>,           // 48 bytes
        /// Runtime Measurement Register 3
        rt_mr3: vector<u8>,           // 48 bytes
        /// User-provided data that can be included in the report
        report_data: vector<u8>,      // 64 bytes
    }

    /// Represents the QE Report Certification Data, which contains the Quoting Enclave's report
    /// and associated certification information
    /// Reference: https://github.com/intel/SGX-TDX-DCAP-QuoteVerificationLibrary/blob/16b7291a7a86e486fdfcf1dfb4be885c0cc00b4e/Src/AttestationLibrary/src/QuoteVerification/QuoteStructures.h#L143-L151
    public struct QEReportCertificationData has store, copy, drop {
        /// The Quoting Enclave's report containing measurements and identity information
        qe_report: EnclaveReport,
        /// Cryptographic signature of the QE report (typically ECDSA)
        qe_report_signature: vector<u8>,
        /// Authentication data specific to the Quoting Enclave
        qe_auth_data: QEAuthData,
        /// Additional certification data used to verify the quote chain of trust
        certification: CertificationData
    }

    /// Represents the ECDSA Quote V4 Authentication Data structure that contains
    /// the cryptographic proof of the quote's authenticity.
    ///
    /// This structure includes the ECDSA signature of the quote, the public attestation
    /// key used for verification, and the Quoting Enclave's certification data that
    /// establishes the chain of trust.
    ///
    /// This structure is modified from the original definition, since we are expecting
    /// the certification data to be of certification type 6 [`QEReportCertificationData`].
    /// Reference: https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/45554a754ba8c03342cc394831fa7f04db08805c/QuoteGeneration/quote_wrapper/common/inc/sgx_quote_4.h#L85-L96
    public struct EcdsaQuoteV4AuthData has store, copy, drop {
        /// ECDSA signature
        ecdsa_signature: vector<u8>, // 64 bytes
        /// ECDSA attestation key
        ecdsa_attestation_key: vector<u8>, // 64 bytes
        /// Quoting Enclave report certification data
        qe_report_cert_data: QEReportCertificationData
    }

    /// Represents a V4 TDX Quote, which is a cryptographically signed attestation structure
    /// that provides proof of the TDX (Trust Domain Extensions) environment's identity and state.
    public struct V4TDXQuote has store, copy, drop {
        /// Contains metadata about the quote format and version
        header: Header,
        /// Contains the TD 1.0 report measurements and attributes that define
        /// the identity and state of the TDX environment
        report_body: TD10ReportBody,
        /// Contains the ECDSA signature, attestation key, and certification data
        /// that proves the authenticity of the quote
        auth_data: EcdsaQuoteV4AuthData
    }

    /// Represents the Quote Header structure containing metadata about the quote
    /// Reference: https://github.com/intel/SGX-TDX-DCAP-QuoteVerificationLibrary/blob/16b7291a7a86e486fdfcf1dfb4be885c0cc00b4e/Src/AttestationLibrary/src/QuoteVerification/QuoteStructures.h#L42-L53
    public struct Header has store, copy, drop { 
        /// Version of the quote format
        version: u16, // 2 bytes
        /// Type of attestation key used
        attestation_key_type: u16, // 2 bytes
        /// Type of TEE (Trusted Execution Environment)
        tee_type: u32,  // 4 bytes
        /// Quoting Enclave Security Version Number
        qe_svn: u16,  // 2 bytes
        /// Provisioning Certification Enclave Security Version Number
        pce_svn: u16,  // 2 bytes
        /// Vendor ID of the Quoting Enclave
        qe_vendor_id: u128,  // 16 bytes
        /// User-provided data
        user_data: vector<u8>,  // 20 bytes
    }

    /// Represents an Enclave Report containing measurements and identity information
    /// Reference: https://github.com/intel/SGX-TDX-DCAP-QuoteVerificationLibrary/blob/16b7291a7a86e486fdfcf1dfb4be885c0cc00b4e/Src/AttestationLibrary/src/QuoteVerification/QuoteStructures.h#L63-L80
    public struct EnclaveReport has store, copy, drop {
        /// CPU Security Version Number
        cpu_svn: u128,  // 16 bytes
        /// Miscellaneous select bits
        misc_select: u32,  // 4 bytes
        /// Reserved field 1
        reserved1: vector<u8>,  // 28 bytes
        /// Enclave attributes
        attributes: u128,  // 16 bytes
        /// Measurement of the code/data in the enclave
        mr_enclave: u256,  // 32 bytes
        /// Reserved field 2
        reserved2: u256,  // 32 bytes
        /// Measurement of the enclave's signer
        mr_signer: u256,  // 32 bytes
        /// Reserved field 3
        reserved3: vector<u8>,  // 96 bytes
        /// Product ID of the ISV
        isv_prod_id: u16,
        /// Security Version Number of the ISV
        isv_svn: u16,
        /// Reserved field 4
        reserved4: vector<u8>,  // 60 bytes
        /// Report specific data
        report_data: vector<u8>,  // 64 bytes
    }

    /// Represents QE Authentication Data
    /// Reference: https://github.com/intel/SGX-TDX-DCAP-QuoteVerificationLibrary/blob/16b7291a7a86e486fdfcf1dfb4be885c0cc00b4e/Src/AttestationLibrary/src/QuoteVerification/QuoteStructures.h#L128-L133
    public struct QEAuthData has store, copy, drop {
        /// Size of the parsed data
        parsed_data_size: u16,
        /// Authentication data
        data: vector<u8>
    }

    /// Represents Certification Data
    /// Reference: https://github.com/intel/SGX-TDX-DCAP-QuoteVerificationLibrary/blob/16b7291a7a86e486fdfcf1dfb4be885c0cc00b4e/Src/AttestationLibrary/src/QuoteVerification/QuoteStructures.h#L135-L141
    public struct CertificationData has store, copy, drop {
        /// Type of certification
        cert_type: u16,
        /// Size of certification data
        cert_data_size: u32,
        /// PCK collateral data
        pck: PCKCollateral
    }

    // ============================== CUSTOM TYPES ==============================

    /// Represents PCK Collateral information
    public struct PCKCollateral has store, copy, drop {
        /// PCK certificate chain
        pck_chain: vector<vector<u8>>,
        /// PCK certificate TCB extension
        pck_extension: PCKCertTCB
    }

    /// Represents PCK Certificate TCB information
    public struct PCKCertTCB has store, copy, drop {
        /// PCE Security Version Number
        pcesvn: u16,
        /// CPU Security Version Numbers
        cpusvns: vector<u8>,
        /// FMSPC (Family-Model-Stepping-Platform-CustomSKU) bytes
        fmspc_bytes: vector<u8>,
        /// PCE ID bytes
        pceid_bytes: vector<u8>
    }

    /// Creates a new TD10ReportBody structure with validation checks.
    /// 
    /// This function constructs a TD 1.0 Report Body structure that represents the measurements
    /// and attributes of a Trust Domain (TD) environment. It performs validation checks on all
    /// input vectors to ensure they match the expected lengths defined by the module constants.
    ///
    /// # Arguments
    /// * `tee_tcb_svn` - TCB Security Version Numbers (16 bytes)
    /// * `mr_seam` - Measurement Register for SEAM module (48 bytes)
    /// * `mrsigner_seam` - Measurement of SEAM module signer (48 bytes)
    /// * `seam_attributes` - SEAM module security attributes (8 bytes)
    /// * `td_attributes` - Trust Domain security attributes (8 bytes)
    /// * `xfam` - Extended Feature Activation Mask (8 bytes)
    /// * `mr_td` - Trust Domain Measurement Register (48 bytes)
    /// * `mr_config_id` - TD Configuration ID Measurement (48 bytes)
    /// * `mr_owner` - TD Owner Identity Measurement (48 bytes)
    /// * `mr_owner_config` - TD Owner Configuration Measurement (48 bytes)
    /// * `rt_mr0` - Runtime Measurement Register 0 (48 bytes)
    /// * `rt_mr1` - Runtime Measurement Register 1 (48 bytes)
    /// * `rt_mr2` - Runtime Measurement Register 2 (48 bytes)
    /// * `rt_mr3` - Runtime Measurement Register 3 (48 bytes)
    /// * `report_data` - User-provided report data (64 bytes)
    ///
    /// # Returns
    /// * `TD10ReportBody` - The constructed report body structure
    ///
    /// # Aborts
    /// * `EInvalidLength` - If any input vector doesn't match its expected length
    public fun create_td10_report_body(
        tee_tcb_svn: vector<u8>,
        mr_seam: vector<u8>,
        mrsigner_seam: vector<u8>,
        seam_attributes: vector<u8>,
        td_attributes: vector<u8>,
        xfam: vector<u8>,
        mr_td: vector<u8>,
        mr_config_id: vector<u8>,
        mr_owner: vector<u8>,
        mr_owner_config: vector<u8>,
        rt_mr0: vector<u8>,
        rt_mr1: vector<u8>,
        rt_mr2: vector<u8>,
        rt_mr3: vector<u8>,
        report_data: vector<u8>,
    ): TD10ReportBody {
        // Validate lengths
        assert!(vector::length(&tee_tcb_svn) == TEE_TCB_SVN_LENGTH, EInvalidLength);
        assert!(vector::length(&mr_seam) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&mrsigner_seam) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&seam_attributes) == ATTRIBUTES_LENGTH, EInvalidLength);
        assert!(vector::length(&td_attributes) == ATTRIBUTES_LENGTH, EInvalidLength);
        assert!(vector::length(&xfam) == ATTRIBUTES_LENGTH, EInvalidLength);
        assert!(vector::length(&mr_td) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&mr_config_id) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&mr_owner) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&mr_owner_config) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&rt_mr0) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&rt_mr1) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&rt_mr2) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&rt_mr3) == MR_LENGTH, EInvalidLength);
        assert!(vector::length(&report_data) == REPORT_DATA_LENGTH, EInvalidLength);

        TD10ReportBody {
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
        }
    }

     /// Creates a new EcdsaQuoteV4AuthData structure with validation checks.
    /// 
    /// This function constructs the authentication data portion of a V4 TDX Quote,
    /// which includes the ECDSA signature, attestation key, and certification data.
    /// It validates that the signature and attestation key lengths match the expected
    /// SIGNATURE_LENGTH (64 bytes).
    ///
    /// # Arguments
    /// * `signature` - The ECDSA 256-bit signature (must be 64 bytes)
    /// * `attestation_key` - The ECDSA attestation public key (must be 64 bytes)
    /// * `qe_report_cert_data` - The Quoting Enclave report certification data
    ///
    /// # Returns
    /// * `EcdsaQuoteV4AuthData` - The constructed authentication data structure
    ///
    /// # Aborts
    /// * `EInvalidLength` - If either the signature or attestation key length is not 64 bytes
    public fun create_ecdsa_quote_v4_auth_data(
        signature: vector<u8>,
        attestation_key: vector<u8>,
        qe_report_cert_data: QEReportCertificationData,
    ): EcdsaQuoteV4AuthData {
        assert!(vector::length(&signature) == SIGNATURE_LENGTH, EInvalidLength);
        assert!(vector::length(&attestation_key) == SIGNATURE_LENGTH, EInvalidLength);

        EcdsaQuoteV4AuthData {
            ecdsa_signature: signature,
            ecdsa_attestation_key: attestation_key,
            qe_report_cert_data
        }
    }

    /// Creates a new QEReportCertificationData structure.
    /// 
    /// This function constructs a QE Report Certification Data structure that contains
    /// the Quoting Enclave's report and associated certification information. This data
    /// is crucial for establishing the authenticity and chain of trust in the TDX
    /// attestation process.
    ///
    /// # Arguments
    /// * `qe_report` - The Quoting Enclave's report containing measurements and identity information
    /// * `qe_report_signature` - Cryptographic signature of the QE report (ECDSA)
    /// * `qe_auth_data` - Authentication data specific to the Quoting Enclave
    /// * `certification` - Additional certification data used to verify the quote chain of trust
    ///
    /// # Returns
    /// * `QEReportCertificationData` - The constructed QE report certification data structure
    /// 
    /// # Aborts
    /// * `EInvalidLength` - If the QE report signature length is not 64 bytes
    public fun create_qe_report_cert_data(
        qe_report: EnclaveReport,
        qe_report_signature: vector<u8>,
        qe_auth_data: QEAuthData,
        certification: CertificationData,
    ): QEReportCertificationData {
        assert!(vector::length(&qe_report_signature) == SIGNATURE_LENGTH, EInvalidLength);

        QEReportCertificationData {
            qe_report,
            qe_report_signature,
            qe_auth_data,
            certification,
        }
    }

    /// Creates a new QEAuthData structure with validation checks.
    /// 
    /// This function constructs a QE Authentication Data structure that contains
    /// the parsed data size and the actual authentication data. It validates that
    /// the length of the provided data matches the specified parsed_data_size.
    ///
    /// # Arguments
    /// * `parsed_data_size` - The expected size of the authentication data
    /// * `data` - The actual authentication data bytes
    ///
    /// # Returns
    /// * `QEAuthData` - The constructed QE authentication data structure
    ///
    /// # Aborts
    /// * `EInvalidLength` - If the length of data doesn't match parsed_data_size
    public fun create_qe_auth_data(
        parsed_data_size: u16,
        data: vector<u8>,
    ): QEAuthData {
        assert!(vector::length(&data) == parsed_data_size as u64, EInvalidLength);
        QEAuthData {
            parsed_data_size,
            data,
        }
    }

    /// Creates a new CertificationData structure.
    /// 
    /// This function constructs a Certification Data structure that contains information
    /// about the type of certification, its size, and the PCK (Platform Certification Key)
    /// collateral data used in the attestation process.
    ///
    /// # Arguments
    /// * `cert_type` - The type of certification being used
    /// * `cert_data_size` - The size of the certification data in bytes
    /// * `pck` - The Platform Certification Key collateral data
    ///
    /// # Returns
    /// * `CertificationData` - The constructed certification data structure
    public fun create_certification_data(
        cert_type: u16,
        cert_data_size: u32,
        pck: PCKCollateral,
    ): CertificationData {
        CertificationData {
            cert_type,
            cert_data_size,
            pck,
        }
    }

    /// Creates a new PCKCollateral structure.
    /// 
    /// This function constructs a Platform Certification Key (PCK) Collateral structure
    /// that contains the certificate chain and TCB (Trusted Computing Base) extension
    /// information used to verify the platform's authenticity.
    ///
    /// # Arguments
    /// * `pck_chain` - Vector of certificate chain components
    /// * `pck_extension` - TCB extension information for the PCK certificate
    ///
    /// # Returns
    /// * `PCKCollateral` - The constructed PCK collateral structure
    public fun create_pck_collateral(
        pck_chain: vector<vector<u8>>,
        pck_extension: PCKCertTCB,
    ): PCKCollateral {
        PCKCollateral {
            pck_chain,
            pck_extension,
        }
    }
    
    /// Creates a new PCKCertTCB structure.
    /// 
    /// This function constructs a PCK Certificate TCB structure that contains various
    /// platform-specific security version numbers and identification information used
    /// in the attestation process.
    ///
    /// # Arguments
    /// * `pcesvn` - Platform Configuration Enclave Security Version Number
    /// * `cpusvns` - CPU Security Version Numbers
    /// * `fmspc_bytes` - Family-Model-Stepping-Platform-CustomSKU identification bytes
    /// * `pceid_bytes` - Platform Configuration Enclave ID bytes
    ///
    /// # Returns
    /// * `PCKCertTCB` - The constructed PCK certificate TCB structure
    public fun create_pck_cert_tcb(
        pcesvn: u16,
        cpusvns: vector<u8>,
        fmspc_bytes: vector<u8>,
        pceid_bytes: vector<u8>,
    ): PCKCertTCB {
        PCKCertTCB {
            pcesvn,
            cpusvns,
            fmspc_bytes,
            pceid_bytes,
        }
    }

    /// Creates a new EnclaveReport structure.
    /// 
    /// This function constructs an Enclave Report structure that contains measurements and
    /// identity information about an enclave. The report includes various security-related
    /// measurements, version numbers, and reserved fields as defined in the Intel SGX/TDX
    /// specification.
    ///
    /// # Arguments
    /// * `cpu_svn` - CPU Security Version Number (16 bytes)
    /// * `misc_select` - Miscellaneous select bits for enclave configuration
    /// * `reserved1` - Reserved field (28 bytes)
    /// * `attributes` - Enclave attributes defining its properties
    /// * `mr_enclave` - Measurement of the code/data in the enclave (32 bytes)
    /// * `reserved2` - Reserved field (32 bytes)
    /// * `mr_signer` - Measurement of the enclave's signer (32 bytes)
    /// * `reserved3` - Reserved field (96 bytes)
    /// * `isv_prod_id` - Product ID assigned by the Independent Software Vendor
    /// * `isv_svn` - Security Version Number assigned by the ISV
    /// * `reserved4` - Reserved field (60 bytes)
    /// * `report_data` - Custom report data (64 bytes)
    ///
    /// # Returns
    /// * `EnclaveReport` - The constructed enclave report structure
    public fun create_enclave_report(
        cpu_svn: u128,
        misc_select: u32,
        reserved1: vector<u8>,
        attributes: u128,
        mr_enclave: u256,
        reserved2: u256,
        mr_signer: u256,
        reserved3: vector<u8>,
        isv_prod_id: u16,
        isv_svn: u16,
        reserved4: vector<u8>,
        report_data: vector<u8>,
    ): EnclaveReport {
        EnclaveReport {
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
            report_data,
        }
    }

    /// Creates a new V4 TDX Quote structure.
    /// 
    /// This function constructs a V4 TDX Quote structure that represents a complete
    /// attestation report for a Trust Domain Extensions (TDX) environment. The quote
    /// includes a header with metadata, a report body containing measurements and
    /// attributes, and authentication data that proves the quote's authenticity.
    ///
    /// # Arguments
    /// * `header` - Reference to the quote header containing metadata about format and version
    /// * `report_body` - The TD 1.0 report body containing measurements and attributes
    /// * `auth_data` - The ECDSA authentication data including signature and certification
    ///
    /// # Returns
    /// * `V4TDXQuote` - The constructed V4 TDX quote structure
    public fun create_v4_tdx_quote(
        header: &Header,
        report_body: TD10ReportBody,
        auth_data: EcdsaQuoteV4AuthData,
    ): V4TDXQuote {
        V4TDXQuote {
            header: *header,
            report_body,
            auth_data,
        }
    }

    /// Returns the version of the quote header
    /// 
    /// # Arguments
    /// * `header` - The quote header
    ///
    /// # Returns
    /// * `u16` - The version of the quote header
    public fun get_header_version(header: &Header): u16 {
        header.version
    }

    /// Returns the attestation key type of the quote header
    /// 
    /// # Arguments
    /// * `header` - The quote header
    ///
    /// # Returns
    /// * `u16` - The attestation key type
    public fun get_attestation_key_type(header: &Header): u16 {
        header.attestation_key_type
    }

    /// Returns the QE vendor ID of the quote header
    /// 
    /// # Arguments
    /// * `header` - The quote header
    ///
    /// # Returns
    /// * `vector<u8>` - The QE vendor ID
    public fun get_qe_vendor_id(header: &Header): u128 {
        header.qe_vendor_id
    }

    /// Returns the TEE type of the quote header
    /// 
    /// # Arguments
    /// * `header` - The quote header
    ///
    /// # Returns
    /// * `vector<u8>` - The TEE type
    public fun get_tee_type(header: &Header): u32 {
        header.tee_type
    }
}
