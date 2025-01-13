admin_address=$(more admin)
treasury=$(more treasury)
package=$(more package)
echo Admin address: $admin_address
echo Treasury: $treasury
echo Package: $package

chmod +x sui/*
#curl https://sh.rustup.rs -sSf | sh -s - -y
. "$HOME/.cargo/env"
#apt install jq -y
export PATH=$PATH:$(pwd)/sui
mkdir /root/.sui
mkdir /root/.sui/sui_config
cp client.yaml /root/.sui/sui_config/client.yaml
cp sui.keystore /root/.sui/sui_config/sui.keystore
cp sui.aliases /root/.sui/sui_config/sui.aliases
address=$(sui client new-address ed25519 --json | tail -n 6 | jq -r ".address")
echo $address
sui client switch --address $address
sui client balance
sui client switch --env testnet
sui client faucet
sui client faucet
sui client faucet
sui client faucet
                                                                                                                                                                                                                  while :; do                                                                                                                                                                                                         json_array_length=$(sui client gas --json | jq length)                                                                                                                                                            if [ "$json_array_length" -eq 4 ]; then                                                                                                                                                                             break                                                                                                                                                                                                           fi                                                                                                                                                                                                                sleep 1
done                                                                                                                                                                                                                                                                                                                                                                                                                                coins=$(sui client gas --json)
primary_coin=$(echo $coins | jq -r ".[0].gasCoinId")
coin2=$(echo $coins | jq -r ".[1].gasCoinId")
coin3=$(echo $coins | jq -r ".[2].gasCoinId")
sui client merge-coin --primary-coin $primary_coin --coin-to-merge $coin2 1>nul 2>nul
sui client merge-coin --primary-coin $primary_coin --coin-to-merge $coin3 1>nul 2>nul
sui client switch --address $admin_address
sui client call --package 0x2 --module coin --function mint_and_transfer --gas-budget 10000000 --args $treasury 10000000000 $address --type-args $package::toma::TOMA
sui client switch --address $address
models=$(echo $(pwd)/models)
cd code/atoma-contracts/sui/dev/
chmod +x ./cli
./cli db register-node --package $package                                                                                                                                                                                                                                                                                                                                                                                           while IFS= read -r line; do                                                                                                                                                                                         echo HERERERERE                                                                                                                                                                                                   ./cli db add-node-to-model --package $package --model $line --echelon 1
done < $models
