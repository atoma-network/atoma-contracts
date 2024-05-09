module atoma::utils {
    public fun random_u32(ctx: &mut TxContext): u32 { 
        let mut buffer = sui::address::to_bytes(
            tx_context::fresh_object_address(ctx)
        );

        let num_of_bytes = 4;
        let mut result: u32 = 0;
        let mut i = 0;
        while (i < num_of_bytes) {
            let byte = buffer.pop_back();
            result = (result << 4) + (byte as u32);
            i = i + 1;
        };
        result
    }

    public fun random_u64(ctx: &mut TxContext): u64 {
        let mut buffer = sui::address::to_bytes(
            tx_context::fresh_object_address(ctx)
        );

        let num_of_bytes = 8;
        let mut result: u64 = 0;
        let mut i = 0;
        while (i < num_of_bytes) {
            let byte = buffer.pop_back();
            result = (result << 8) + (byte as u64);
            i = i + 1;
        };
        result
    }

    public fun random_u256(ctx: &mut TxContext): u256 {
        let mut buffer = sui::address::to_bytes(
            tx_context::fresh_object_address(ctx)
        );

        let num_of_bytes = 32;
        let mut result: u256 = 0;
        let mut i = 0;
        while (i < num_of_bytes) {
            let byte = buffer.pop_back();
            result = (result << 32) + (byte as u256);
            i = i + 1;
        };
        result
    }

    #[test]
    fun test_random_u32() { 
        let mut ctx = tx_context::new_from_hint(
            @0x1,
            9908,
            10,
            10,
            0
        );
        random_u32(&mut ctx)
    }

    #[test]
    fun test_random_u64() {
        let mut ctx = tx_context::new_from_hint(
            @0x1,
            9908,
            10,
            10,
            0
        );
        random_u64(&mut ctx);
    }

    #[test]
    fun test_random_u256() {
        let mut ctx = tx_context::new_from_hint(
            @0x1,
            9908,
            10,
            10,
            0
        );
        random_u256(&mut ctx);
    }
}
