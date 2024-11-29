module atoma_tee::utils {
    //! Utility functions for the Atoma TEE package
    
    const EInvalidVectorLength: u64 = 0;

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
    public(package) fun extract_bytes(bytes: vector<u8>, start: u64, len: u64): vector<u8> { 
        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < len) { 
            vector::push_back(&mut result, *vector::borrow(&bytes, start + i));
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
    /// let value = le_bytes_to_u16(bytes); // Returns 0x1234 (4660 in decimal)
    /// ```
    public(package) fun le_bytes_to_u16(bytes: vector<u8>): u16 { 
        assert!(vector::length(&bytes) == 2, EInvalidVectorLength);
        (((*vector::borrow(&bytes, 1) as u16) << 8) | (*vector::borrow(&bytes, 0) as u16))
    }

    /// Converts a 4-byte vector into a u32 value using little-endian byte order
    /// 
    /// # Arguments
    /// * `bytes` - Vector containing exactly 4 bytes in little-endian order
    /// 
    /// # Returns
    /// * `u32` - The converted 32-bit unsigned integer
    /// 
    /// # Aborts
    /// * `EInvalidVectorLength` - If the input vector does not contain exactly 4 bytes
    /// 
    /// # Example
    /// ```
    /// let bytes = vector[0x78, 0x56, 0x34, 0x12];  // 0x12345678 in little-endian
    /// let value = le_bytes_to_u32(bytes); // Returns 0x12345678 (305419896 in decimal)
    /// ```
    public(package) fun le_bytes_to_u32(bytes: vector<u8>): u32 { 
        assert!(vector::length(&bytes) == 4, EInvalidVectorLength);
        (((*vector::borrow(&bytes, 3) as u32) << 24) |
        ((*vector::borrow(&bytes, 2) as u32) << 16) |
        ((*vector::borrow(&bytes, 1) as u32) << 8) |
        (*vector::borrow(&bytes, 0) as u32))
    }

    /// Converts a vector of 8 bytes into a u64 value using little-endian byte order
    /// This implementation uses le_bytes_to_u32 to convert two 4-byte chunks
    /// 
    /// # Arguments
    /// * `bytes` - Vector containing exactly 8 bytes in little-endian order
    /// 
    /// # Returns
    /// * `u64` - The converted 64-bit unsigned integer
    /// 
    /// # Aborts
    /// * `EInvalidVectorLength` - If the input vector does not contain exactly 8 bytes
    /// 
    /// # Example
    /// ```
    /// let bytes = vector[0xEF, 0xCD, 0xAB, 0x90, 0x78, 0x56, 0x34, 0x12];
    /// let value = le_bytes_to_u64(bytes); // Returns 0x1234567890ABCDEF
    /// ```
    public(package) fun le_bytes_to_u64(bytes: vector<u8>): u64 {
        assert!(vector::length(&bytes) == 8, EInvalidVectorLength);
        ((le_bytes_to_u32(extract_bytes(bytes, 4, 4)) as u64) << 32 | 
            (le_bytes_to_u32(extract_bytes(bytes, 0, 4)) as u64))
    }

    /// Converts a vector of 16 bytes into a u128 value using little-endian byte order
    /// This implementation uses le_bytes_to_u64 to convert two 8-byte chunks
    /// 
    /// # Arguments
    /// * `bytes` - Vector containing exactly 16 bytes in little-endian order
    /// 
    /// # Returns
    /// * `u128` - The converted 128-bit unsigned integer
    /// 
    /// # Aborts
    /// * `EInvalidVectorLength` - If the input vector does not contain exactly 16 bytes
    /// 
    /// # Example
    /// ```
    /// let bytes = vector[0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88,
    ///                    0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00];
    /// let value = le_bytes_to_u128(bytes); // Returns 0x00112233445566778899AABBCCDDEEFF
    /// ```
    public(package) fun le_bytes_to_u128(bytes: vector<u8>): u128 {
        assert!(vector::length(&bytes) == 16, EInvalidVectorLength);
        (le_bytes_to_u64(extract_bytes(bytes, 0, 8)) as u128) | 
            ((le_bytes_to_u64(extract_bytes(bytes, 8, 8)) as u128) << 64)
    }

    /// Converts a vector of 32 bytes into a u256 value using little-endian byte order
    /// This implementation uses le_bytes_to_u128 to convert two 16-byte chunks
    /// 
    /// # Arguments
    /// * `bytes` - Vector containing exactly 32 bytes in little-endian order
    /// 
    /// # Returns
    /// * `u256` - The converted 256-bit unsigned integer
    /// 
    /// # Aborts
    /// * `EInvalidVectorLength` - If the input vector does not contain exactly 32 bytes
    /// 
    /// # Example
    /// ```
    /// let bytes = vector[
    ///     0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88,
    ///     0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00,
    ///     0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88,
    ///     0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00
    /// ];
    /// let value = le_bytes_to_u256(bytes); // Returns 0x00112233...EEFF (32 bytes)
    /// ```
    public(package) fun le_bytes_to_u256(bytes: vector<u8>): u256 {
        assert!(vector::length(&bytes) == 32, EInvalidVectorLength);
        (le_bytes_to_u128(extract_bytes(bytes, 0, 16)) as u256) | 
            ((le_bytes_to_u128(extract_bytes(bytes, 16, 16)) as u256) << 128)
    }

    /// Converts a 64-bit unsigned integer into a vector of bytes using little-endian byte order
    /// 
    /// # Arguments
    /// * `value` - The u64 integer to convert
    /// 
    /// # Returns
    /// * `vector<u8>` - Vector containing 8 bytes representing the integer in little-endian order
    /// 
    /// # Example
    /// ```
    /// let value = 0x1234567890ABCDEF;
    /// let bytes = int_to_le_bytes(value); // Returns [EF, CD, AB, 90, 78, 56, 34, 12]
    /// ```
    public(package) fun int_to_le_bytes(value: u64): vector<u8> {
        let mut bytes = vector::empty();
        let mut i = 0;
        while (i < 8) {
            vector::push_back(&mut bytes, ((value >> (i * 8)) & 0xFF as u8));
            i = i + 1;
        };
        bytes
    }

    /// Helper function to compare two vectors byte by byte
    /// 
    /// # Arguments
    /// * `a` - First vector to compare
    /// * `b` - Second vector to compare
    /// 
    /// # Returns
    /// * `bool` - True if vectors are identical, false otherwise
    public(package) fun compare_vectors(a: &vector<u8>, b: &vector<u8>): bool {
        let mut i = 0;
        let len = vector::length(a);
        
        while (i < len) {
            if (*vector::borrow(a, i) != *vector::borrow(b, i)) {
                return false
            };
            i = i + 1;
        };
        true
    }
}
