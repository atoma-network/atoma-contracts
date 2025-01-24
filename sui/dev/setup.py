import subprocess
import json
import re
import os
import shutil
from typing import Any


def sui_client(command: str):
    print(command)
    try:
        process = subprocess.run("sui client " + command + " --json", shell=True, check=True, stdout=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(e.stdout.decode())
        raise e
    output = process.stdout.decode()
    return json.loads(output)

def build_atoma(path: str):
    # Get the current path
    pwd = os.getcwd()

    os.chdir(path)

    # Build the Atoma package
    if os.path.exists("atoma_build.json"):
        output_json = json.load(open("atoma_build.json", "r"))
    else:
        # Remove the build folder and Move.lock file
        if os.path.exists("build"):
            shutil.rmtree("build")
        if os.path.exists("Move.lock"):
            os.remove("Move.lock")
        output_json = sui_client("publish --skip-dependency-verification --skip-fetch-latest-git-deps --gas-budget 900000000")
        json.dump(output_json, open("atoma_build.json", "w"), indent=4)
    atoma_package = output_json["events"][0]["packageId"]
    atoma_db = output_json["events"][0]["parsedJson"]["db"]
    atoma_manager_badge = output_json["events"][0]["parsedJson"]["manager_badge"]

    # Return to the original path
    os.chdir(pwd)
    return atoma_package, atoma_db, atoma_manager_badge


paths = [os.path.join("..", "packages"), os.path.join("sui", "packages")]
atoma_paths = [os.path.join(path, "atoma") for path in paths]

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
models = [("unsloth/Llama-3.2-1B-Instruct", TEXT2TEXT, 1)]


output_json = sui_client(f'call --package "{atoma_package}" --module "db" --function "register_node_entry" --args "{atoma_db}" --gas-budget 900000000')
node_badge = output_json["events"][0]["parsedJson"]["badge_id"]
small_id = output_json["events"][0]["parsedJson"]["node_small_id"]["inner"]

# Add models
for model, model_type, echelon in models:
    task = sui_client(
        f'call --package "{atoma_package}" --module "db" --function "create_task_entry" --args "{atoma_db}" "{atoma_manager_badge}" 0 ["{model}"] ["0"] ["50"] true'
    )
    task_small_id = task["events"][0]["parsedJson"]["task_small_id"]["inner"]

    sui_client(f'call --package "{atoma_package}" --module "db" --function "subscribe_node_to_task" --args "{atoma_db}" {node_badge} {task_small_id} 10000000')

print("Atoma_package: ", atoma_package)
print("Atoma_db: ", atoma_db)
print("Badge_id: ", node_badge)
print("Small_id: ", small_id)