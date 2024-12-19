module secret_guessing::secret_guessing {
    //! # AI Agent Secret Guessing Game
    //!
    //! A blockchain-based guessing game that interacts with an AI Language Model (LLM) running in a 
    //! Trusted Execution Environment (TEE) node. The AI agent holds a secret in its private system prompt
    //! and players attempt to discover it through strategic interactions.
    //!
    //! ## Game Mechanics
    //! - An AI agent (LLM) runs, using Atoma's private AI compute, in a TEE node with a secret embedded in its system prompt
    //! - Players engage in a conversation with the AI to try to deduce the secret
    //! - Each interaction/guess must be paid for through the smart contract
    //! - The AI agent carefully guards the secret while responding to queries
    //! - Players can use creative questioning and deduction strategies
    //!
    //! ## Economic Model
    //! - Initial interaction fee: X SUI
    //! - Fee increase: +10% per attempt
    //! - All fees accumulate in the prize pool
    //! - First player to extract the secret wins 50% of the pool
    //!
    //! ## Security & AI Integration
    //! - The AI agent runs in a secure TEE environment
    //! - The system prompt and secret are never exposed on-chain
    //! - The LLM is configured to engage while protecting the secret
    //! - Smart contract manages the economic layer and prize distribution
    //! - AI responses are deterministic within the TEE
    //!
    //! ## Social Integration
    //! - Each AI response is automatically shared on Twitter
    //! - Creates a public record of all guess attempts
    //! - Allows community engagement and collective problem-solving
    //! - Builds excitement as players get closer to the secret
    //! - Twitter thread serves as an immutable history of the game
    
    public struct SECRET_GUESSING has drop {}

    /// The package publisher allows upgrades and admin access to other modules.
    fun init(otw: SECRET_GUESSING, ctx: &mut TxContext) {
        // https://examples.sui.io/basics/publisher.html
        sui::package::claim_and_keep(otw, ctx);
    }
}
