import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import seaborn as sns
import os

# --- Configuration ---
CSV_FILE = 'test/poc/log.csv'
OUTPUT_DIR = 'test/poc/plots'
PLOT_1_FILENAME = os.path.join(OUTPUT_DIR, 'plot_1_health_and_profit.jpeg')
PLOT_2_FILENAME = os.path.join(OUTPUT_DIR, 'plot_2_pool_dynamics.jpeg')
PLOT_3_FILENAME = os.path.join(OUTPUT_DIR, 'plot_3_impermanent_loss.jpeg')

# --- Helper Functions ---

def load_and_prepare_data(csv_path):
    """Loads the CSV and prepares it for plotting."""
    # Load the data
    df = pd.read_csv(csv_path)

    # Clean up column names by stripping any whitespace
    df.columns = df.columns.str.strip()

    # Convert timestamp (milliseconds) to datetime objects
    df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')

    # Convert large number columns to numeric types, handling potential errors
    # Convert numeric columns from strings to numbers
    numeric_cols = ['healthFactor', 'collateralValue', 'liabilityValue', 'botHoldings', 'marketPrice1', 'reserve0', 'reserve1', 'marketPrice0']
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors='coerce')

    # Convert healthFactor from 1e18 to a float
    #df['healthFactor'] = df['healthFactor'] / 1e18
    df['healthFactor'] = pd.to_numeric(df['healthFactor'], errors='coerce')/1e18
    
    # Convert botHoldings from 1e18 to a float for easier reading
    df['botHoldings'] = df['botHoldings'] / 1e18

    # Convert marketPrice1 from 1e18 to a float
    df['marketPrice1'] = df['marketPrice1'] / 1e18

    # --- Impermanent Loss Calculation ---
    # Get initial values to calculate the "HODL" portfolio value
    initial_reserve0 = df['reserve0'].iloc[0]
    initial_reserve1 = df['reserve1'].iloc[0]
    
    # Get the initial price of each asset
    initial_price0 = df['marketPrice0'].iloc[0] / 1e12  # USDC, 6 decimals
    initial_price1 = df['marketPrice1'].iloc[0]         # wstETH, already scaled

    # Calculate the value of the initial holdings at current market prices (in USDC)
    df['hodl_value'] = (initial_reserve0 * (df['marketPrice0'] / 1e12)) + \
                       (initial_reserve1 * df['marketPrice1'])
    df['hodl_value'] = df['hodl_value'] / 1e18  # Convert to USDC units

    # Calculate the actual value of the LP's collateral (in USDC)
    df['lp_value'] = df['collateralValue'] / 1e18

    # Impermanent Loss is the difference between HODL value and actual LP value (in USDC)
    df['impermanent_loss'] = df['hodl_value'] - df['lp_value']

    return df

def setup_plot_style():
    """Sets a professional style for the plots."""
    sns.set_theme(style="darkgrid")
    plt.rcParams['figure.figsize'] = (15, 7)
    plt.rcParams['figure.dpi'] = 150

def format_x_axis(ax):
    """Formats the x-axis to display dates nicely."""
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d'))
    plt.gcf().autofmt_xdate() # Auto-rotate date labels

# --- Plotting Functions ---

def plot_health_and_profit(df):
    fig, ax1 = plt.subplots(figsize=(12, 6))
    color = 'tab:blue'
    ax1.set_ylabel('LP Health Factor', color=color)
    ax1.plot(df['timestamp'], df['healthFactor'], color=color, label='Health Factor')
    ax1.tick_params(axis='y', labelcolor=color)

    # Draw the liquidation threshold at y=1.0
    ax1.axhline(y=1.0, color='red', linestyle='--', linewidth=1, label='Liquidation Threshold (1.0)')

    # ← add this so 1.0 isn’t off-screen
    ax1.set_ylim(0, df['healthFactor'].max() * 1.05)

    ax2 = ax1.twinx()
    color = 'tab:green'
    ax2.set_ylabel('Bot Holdings (Value in USDC)', color=color)
    ax2.plot(df['timestamp'], df['botHoldings'], color=color, label='Bot Holdings')
    ax2.tick_params(axis='y', labelcolor=color)

    # Combine legends
    lines, labels = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines + lines2, labels + labels2, loc='upper left')

    plt.title('LP Health vs. Arbitrage Bot Profitability')
    format_x_axis(ax1)
    fig.tight_layout()
    fig.legend(loc="upper right", bbox_to_anchor=(1,1), bbox_transform=ax1.transAxes)
    
    plt.savefig(PLOT_1_FILENAME)
    plt.close()
    print(f"Saved plot to {PLOT_1_FILENAME}")

def plot_pool_dynamics(df):
    """Plots pool reserves against the market price of asset 1."""
    fig, ax1 = plt.subplots()

    # Plot reserves on the left axis
    color = 'tab:purple'
    ax1.set_xlabel('Date')
    ax1.set_ylabel('Pool Reserves', color=color)
    ax1.plot(df['timestamp'], df['reserve0'], color='tab:orange', label='Reserve0 (USDC)')
    ax1.plot(df['timestamp'], df['reserve1'], color='tab:purple', label='Reserve1 (wstETH)')
    ax1.tick_params(axis='y', labelcolor=color)
    
    # Create a second y-axis for the market price
    ax2 = ax1.twinx()
    color = 'tab:cyan'
    ax2.set_ylabel('Market Price of Asset1 (wstETH in USDC)', color=color)
    ax2.plot(df['timestamp'], df['marketPrice1'], color=color, linestyle='--', label='Market Price (Asset1)')
    ax2.tick_params(axis='y', labelcolor=color)

    # Final touches
    plt.title('Pool Reserves vs. Market Price', fontsize=16)
    format_x_axis(ax1)
    fig.tight_layout()
    fig.legend(loc="upper right", bbox_to_anchor=(1,1), bbox_transform=ax1.transAxes)

    plt.savefig(PLOT_2_FILENAME)
    plt.close()
    print(f"Saved plot to {PLOT_2_FILENAME}")

def plot_impermanent_loss(df):
    """Plots the impermanent loss of the LP position over time."""
    fig, ax = plt.subplots()

    ax.plot(df['timestamp'], df['impermanent_loss'], color='red', label='Impermanent Loss')

    ax.set_xlabel('Date')
    ax.set_ylabel('Impermanent Loss (Value in USDC)', color='red')
    ax.tick_params(axis='y', labelcolor='red')
    
    # Add a zero line for reference
    ax.axhline(y=0, color='grey', linestyle='--', linewidth=1)

    plt.title('LP Impermanent Loss Over Time', fontsize=16)
    format_x_axis(ax)
    fig.tight_layout()
    plt.legend()
    
    plt.savefig(PLOT_3_FILENAME)
    plt.close()
    print(f"Saved plot to {PLOT_3_FILENAME}")


# --- Main Execution ---

if __name__ == "__main__":
    # Ensure output directory exists
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    # Load and plot data
    try:
        data = load_and_prepare_data(CSV_FILE)
        setup_plot_style()
        plot_health_and_profit(data)
        plot_pool_dynamics(data)
        plot_impermanent_loss(data)
    except FileNotFoundError:
        print(f"Error: The file {CSV_FILE} was not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

