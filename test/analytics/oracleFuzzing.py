import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np

def read_oracle_csv(file_path):
    df = pd.read_csv(file_path)
    # Trim whitespace from column names
    df.columns = df.columns.str.strip()
    print("Column names:", df.columns.tolist())
    print(df.head())
    df = df[df['testCase'] == 1]
    return df

def remove_duplicates(df):
    initial_count = len(df)
    df_cleaned = df.drop_duplicates()
    final_count = len(df_cleaned)
    duplicates_removed = initial_count - final_count
    print(f"\nDuplicates removed: {duplicates_removed}")
    print(f"Original rows: {initial_count}")
    print(f"After removing duplicates: {final_count}")
    return df_cleaned

def analyze_coordinates(df):
    print("\n=== COORDINATE ANALYSIS ===")
    print(f"First column (priceBase) - Min: {df['priceBase'].min()}")
    print(f"First column (priceBase) - Max: {df['priceBase'].max()}")
    print(f"Second column (priceQuote) - Min: {df['priceQuote'].min()}")
    print(f"Second column (priceQuote) - Max: {df['priceQuote'].max()}")

def create_scatter_plot(df):
    plt.figure(figsize=(10, 6))
    # Convert price column to numeric values for coloring
    price_numeric = pd.to_numeric(df['price'], errors='coerce')
    plt.scatter(df['priceBase'], df['priceQuote'], c=price_numeric, cmap='viridis', s=20)
    plt.colorbar(label='Price')
    plt.xlabel('priceBase')
    plt.ylabel('priceQuote')
    plt.title('Price Points: priceBase vs priceQuote')
    plt.savefig('../simulations/out/price_points.png', dpi=300, bbox_inches='tight')
    plt.show()

def main():
    csv_file_path = "../simulations/out/oracles.csv"
    print("Reading oracle CSV data...")
    df = read_oracle_csv(csv_file_path)
    
    df_cleaned = remove_duplicates(df)
    analyze_coordinates(df_cleaned)
    create_scatter_plot(df_cleaned)

if __name__ == "__main__":
    main()
