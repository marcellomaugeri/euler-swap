import json

def convert_price_to_int_str(price_float, decimals):
    """Converts a float price to a fixed-point integer string."""
    return str(int(price_float * (10**decimals)))

def update_config_with_prices(usdc_price_file, wsteth_price_file, config_file):
    """
    Reads price data and updates the config.json file.

    Args:
        usdc_price_file (str): Path to the USDC price JSON file.
        wsteth_price_file (str): Path to the WSTETH price JSON file.
        config_file (str): Path to the config.json to be updated.
    """
    # 1. Load all necessary files
    try:
        with open(usdc_price_file, 'r') as f:
            usdc_data = json.load(f)
        with open(wsteth_price_file, 'r') as f:
            wsteth_data = json.load(f)
        with open(config_file, 'r') as f:
            config_data = json.load(f)
    except FileNotFoundError as e:
        print(f"Error: Could not find file {e.filename}")
        return
    except json.JSONDecodeError as e:
        print(f"Error: Could not parse JSON file. Details: {e}")
        return

    print("Successfully loaded all files.")

    # 2. Create efficient price lookups by timestamp
    usdc_prices = {item[0]: item[1] for item in usdc_data.get('prices', [])}
    wsteth_prices = {item[0]: item[1] for item in wsteth_data.get('prices', [])}

    # 3. Get asset decimals from config
    # Assuming asset[0] is USDC and asset[1] is WSTETH as per the config structure
    usdc_decimals = config_data['assets'][0]['decimals']
    wsteth_decimals = config_data['assets'][1]['decimals']

    # 4. Update initialPrice for each asset
    if wsteth_data['prices']:
        first_timestamp = wsteth_data['prices'][0][0]
        if first_timestamp in usdc_prices and first_timestamp in wsteth_prices:
            initial_usdc_price_float = usdc_prices[first_timestamp]
            initial_wsteth_price_float = wsteth_prices[first_timestamp]

            config_data['assets'][0]['initialPrice'] = convert_price_to_int_str(initial_usdc_price_float, usdc_decimals)
            config_data['assets'][1]['initialPrice'] = convert_price_to_int_str(initial_wsteth_price_float, wsteth_decimals)
            print("Updated initial asset prices.")
        else:
            print("Warning: Could not find matching initial timestamp in both price files. Skipping initialPrice update.")

    # 5. Process and update rounds
    # Create a lookup for existing rounds based on their timestamp
    existing_rounds = {round_data.get('timestamp'): round_data for round_data in config_data.get('rounds', []) if round_data.get('timestamp')}

    new_rounds = []
    # Use WSTETH timestamps as the primary source of truth for rounds
    for timestamp, wsteth_price_float in sorted(wsteth_prices.items()):
        if timestamp not in usdc_prices:
            print(f"Warning: No matching USDC price for timestamp {timestamp}. Skipping this round.")
            continue

        usdc_price_float = usdc_prices[timestamp]

        # Prepare the new price data, converted to fixed-point integers
        price0_str = convert_price_to_int_str(usdc_price_float, usdc_decimals)
        price1_str = convert_price_to_int_str(wsteth_price_float, wsteth_decimals)

        # Check if a round with this timestamp already exists
        if timestamp in existing_rounds:
            round_data = existing_rounds[timestamp]
            round_data['price0'] = price0_str
            round_data['price1'] = price1_str
            new_rounds.append(round_data)
        else:
            # If it does not exist, create a new round
            new_round = {
                "timestamp": timestamp,
                "price0": price0_str,
                "price1": price1_str,
            }
            new_rounds.append(new_round)

    config_data['rounds'] = new_rounds
    print(f"Processed and updated {len(new_rounds)} rounds.")

    # 6. Write the updated data back to config.json
    with open(config_file, 'w') as f:
        json.dump(config_data, f, indent=4)

    print(f"Successfully updated '{config_file}'.")


if __name__ == '__main__':
    # Define the paths to your files
    USDC_PRICE_FILE = 'test/poc/usdc-to-usd-april2025-to-june2025.json'
    WSTETH_PRICE_FILE = 'test/poc/wsteth-to-usd-april2025-to-june2025.json'
    CONFIG_FILE = 'test/poc/config.json'

    update_config_with_prices(USDC_PRICE_FILE, WSTETH_PRICE_FILE, CONFIG_FILE)