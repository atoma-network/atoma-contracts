# Secret Guessing Game Smart Contract

A decentralized guessing game built on the Sui blockchain where participants attempt to guess a secret while competing for a prize pool.

## Overview

The Secret Guessing Game is an interactive smart contract where participants make guesses by paying a fee that increases over time. The collected fees form a treasury pool, which is distributed between the winner (who correctly guesses the secret) and the contract developers.

## How It Works

### Core Mechanics

1. **Making Guesses**
   - Players submit guesses by paying a fee in SUI tokens
   - Each guess is represented by a `GuessBadge` NFT
   - Initial guess fee starts at 1,000 SUI
   - Fee increases by 10% every 100 guesses

2. **Treasury Pool**
   - All fees paid by players go into a shared treasury pool
   - When the secret is correctly guessed:
     - 70% of the pool goes to the winner
     - 30% goes to the development team

3. **Progressive Difficulty**
   - The cost of guessing increases over time
   - Fee increase rate: 10% (100 permille) per 100 guesses
   - This mechanism ensures the game becomes more challenging and valuable over time

### How to Win

1. Submit your guess by calling the `guess_entry` function with:
   - Your guess as a string
   - Sufficient SUI tokens to cover the current fee

2. If your guess is correct:
   - The game ends
   - You receive 70% of the total treasury pool
   - You make history as the winner!

## Technical Details

### Key Components

- `AtomaSecretGuessingDb`: Main contract storage
- `GuessBadge`: NFT representing each guess
- `AtomaSecretGuessingManagerBadge`: Admin access control

### Key Parameters

- Starting Fee: 1,000 SUI
- Fee Update Frequency: Every 100 guesses
- Fee Increase Rate: 10% (100 permille)
- Winner's Share: 70% of treasury
- Developer's Share: 30% of treasury

## Administrative Functions

The contract includes several admin functions for maintenance:

- Update fee increase rate
- Modify developer address
- Change AI agent address
- Adjust starting fee
- Modify fee update frequency

## Events

The contract emits events for:
- Contract initialization
- New guesses
- Treasury distributions

## Security Features

- Access control for administrative functions
- Balance checks for guess submissions
- Protected treasury withdrawal mechanism

## Getting Started

1. Ensure you have sufficient SUI tokens
2. Calculate the current guess fee
3. Submit your guess through a transaction
4. Receive your GuessBadge NFT
5. If correct, claim your prize!

## Note

This is a competitive game where strategy matters. The increasing fee mechanism ensures that early participants pay less for their guesses, while later participants must weigh the higher costs against the larger potential reward from the accumulated treasury.
