use anchor_lang::prelude::*;

declare_id!("Cf8jbVDAgQcNy9TCt9PtSVvZZV5AcX7gpq7vx1ccgbcg");

#[program]
pub mod atoma {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize {}
