import subprocess
import json
import re
import os
import shutil


def sui_client(command: str):
    process = subprocess.run("sui client " + command + " --json", shell=True, check=True, stdout=subprocess.PIPE)
    output = process.stdout.decode()
    return json.loads(output)


def build_toma(path: str):
    # Get the current path
    pwd = os.getcwd()
    # Change to the Toma path
    os.chdir(path)
    # Remove the build folder and Move.lock file
    if os.path.exists("build"):
        shutil.rmtree("build")
    if os.path.exists("Move.lock"):
        os.remove("Move.lock")

    # Change the Move.toml file
    move_toml_file = open("Move.toml", "r")
    move_toml = move_toml_file.read()
    move_toml_file.close()
    move_toml = re.sub(r'(published-at|toma) = "0x[0-9a-f]*"', r'\1 = "0x0"', move_toml)

    move_toml_file = open("Move.toml", "w")
    move_toml_file.write(move_toml)
    move_toml_file.close()

    # Build the Toma package

    if os.path.exists("toma_build.json"):
        output_json = json.load(open("toma_build.json", "r"))
    else:
        output_json = sui_client("publish --skip-dependency-verification")
        json.dump(output_json, open("toma_build.json", "w"), indent=4)
    toma_package = output_json["events"][0]["packageId"]
    toma_faucet = output_json["events"][0]["parsedJson"]["faucet"]
    toma_treasury = output_json["events"][0]["parsedJson"]["treasury"]

    # Change the Move.toml file
    move_toml_file = open("Move.toml", "r")
    move_toml = move_toml_file.read()
    move_toml_file.close()
    move_toml = re.sub(r'(published-at|toma) = "0x0"', rf'\1 = "{toma_package}"', move_toml)

    move_toml_file = open("Move.toml", "w")
    move_toml_file.write(move_toml)
    move_toml_file.close()

    # Return to the original path
    os.chdir(pwd)
    return toma_package, toma_faucet, toma_treasury


def build_atoma(path: str):
    # Get the current path
    pwd = os.getcwd()

    os.chdir(path)

    # Remove the build folder and Move.lock file
    if os.path.exists("build"):
        shutil.rmtree("build")
    if os.path.exists("Move.lock"):
        os.remove("Move.lock")

    # Build the Atoma package
    if os.path.exists("atoma_build.json"):
        output_json = json.load(open("atoma_build.json", "r"))
    else:
        output_json = sui_client("publish --skip-dependency-verification")
        json.dump(output_json, open("atoma_build.json", "w"), indent=4)
    atoma_package = output_json["events"][0]["packageId"]
    atoma_db = output_json["events"][0]["parsedJson"]["db"]
    atoma_manager_badge = output_json["events"][0]["parsedJson"]["manager_badge"]

    # Return to the original path
    os.chdir(pwd)
    return atoma_package, atoma_db, atoma_manager_badge


paths = [os.path.join("..", "packages"), os.path.join("sui", "packages")]
toma_paths = [os.path.join(path, "toma") for path in paths]
atoma_paths = [os.path.join(path, "atoma") for path in paths]

found_toma = False
toma_package = toma_faucet = toma_treasury = None
for toma_path in toma_paths:
    if os.path.exists(toma_path):
        # If there is toma_build.json it will reuse and not deploy new one
        toma_package, toma_faucet, toma_treasury = build_toma(toma_path)
        found_toma = True
        break

if not found_toma:
    print("Toma package not found")
    exit()

atoma_package = atoma_db = atoma_manager_badge = None
for atoma_path in atoma_paths:
    if os.path.exists(atoma_path):
        # If there is atoma_build.json it will reuse and not deploy new one
        atoma_package, atoma_db, atoma_manager_badge = build_atoma(atoma_path)
        break
TEXT2TEXT = 0
TEXT2IMAGE = 1
INPUT_FEE_PER_TOKEN = 1
OUTPUT_FEE_PER_TOKEN = 1
RELATIVE_PERFORMANCE = 100
COLLATERAL = 1
NODE_ECHELON = 1

# Models (model_name, model_type, echelon)
models = [("stable_diffusion_turbo", TEXT2IMAGE, 1), ("mamba_130m", TEXT2TEXT, 1)]

# Enable faucet
sui_client(f'call --package "{toma_package}" --module "toma" --function "enable_faucet" --args "{toma_faucet}" "{toma_treasury}"')

# Set collateral
output_json = sui_client(f'call --package "{toma_package}" --module "toma" --function "faucet" --args "{toma_faucet}" "10000000000"')
toma_wallet = None
for object in output_json["objectChanges"]:
    if re.match(r"0x2::coin::Coin<(0x[0-9a-f]*)::toma::TOMA>", object["objectType"]):
        toma_wallet = object["objectId"]
if not toma_wallet:
    raise Exception("Toma wallet not found")

output_json = sui_client(
    f'call --package "{atoma_package}" --module "db" --function "register_node_entry" --args "{atoma_db}" "{toma_wallet}" --gas-budget 1000000000'
)
node_badge = output_json["events"][0]["parsedJson"]["badge_id"]
small_id = output_json["events"][0]["parsedJson"]["node_small_id"]["inner"]

# Add models
for model, model_type, echelon in models:
    # Add model entry
    sui_client(
        f'call --package "{atoma_package}" --module "db" --function "add_model_entry" --args "{atoma_db}" "{atoma_manager_badge}" "{model}" "{model_type}"'
    )

    # Add model to echelon
    sui_client(
        f'call --package "{atoma_package}" --module "db" --function "add_model_echelon_entry" --args "{atoma_db}" "{atoma_manager_badge}" "{model}" "{echelon}" "{INPUT_FEE_PER_TOKEN}" "{OUTPUT_FEE_PER_TOKEN}" "{RELATIVE_PERFORMANCE}"'
    )

    if echelon == NODE_ECHELON:
        # Add models for node's echelon
        sui_client(f'call --package "{atoma_package}" --module "db" --function "add_node_to_model" --args "{atoma_db}" "{node_badge}" "{model}" "{echelon}"')

print("Toma_package: ", toma_package)
print("Atoma_package: ", atoma_package)
print("Atoma_db: ", atoma_db)
print("Badge_id: ", node_badge)
print("Small_id: ", small_id)
