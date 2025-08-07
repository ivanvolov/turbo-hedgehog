import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from mpl_toolkits.mplot3d import Axes3D

test_case = "-12_false"

def read_oracle_csv(file_path):
    """Read and filter CSV data for the specified test case"""
    df = pd.read_csv(file_path)
    # Trim whitespace from column names
    df.columns = df.columns.str.strip()
    print("Column names:", df.columns.tolist())
    print(df.head())
    df = df[df['testCase'] == test_case]
    return df

def remove_duplicates(df):
    """Remove duplicate rows and report statistics"""
    initial_count = len(df)
    df_cleaned = df.drop_duplicates()
    final_count = len(df_cleaned)
    duplicates_removed = initial_count - final_count
    print(f"\nDuplicates removed: {duplicates_removed}")
    print(f"Original rows: {initial_count}")
    print(f"After removing duplicates: {final_count}")
    return df_cleaned

def analyze_original_p(df):
    """Analyze the original p values from the CSV with detailed statistics"""
    # Convert to numeric values as float
    p_numeric = pd.to_numeric(df['p'], errors='coerce').astype(float)
    
    print(f"\n=== ORIGINAL P ANALYSIS ===")
    print(f"P - Min: {p_numeric.min()}")
    print(f"P - Max: {p_numeric.max()}")
    print(f"P - Mean: {p_numeric.mean()}")
    print(f"P - Std: {p_numeric.std()}")
    print(f"P - Unique values: {p_numeric.nunique()}")
    
    # Show percentiles for better understanding of distribution
    percentiles = [10, 25, 50, 75, 90, 95, 99]
    for p in percentiles:
        print(f"P - {p}th percentile: {p_numeric.quantile(p/100):.6f}")
    
    # Show some sample values
    print(f"First 10 P values: {p_numeric.head(10).tolist()}")
    
    return p_numeric

def analyze_coordinates(df):
    """Analyze the coordinate ranges for price0 and price1"""
    print("\n=== COORDINATE ANALYSIS ===")
    print(f"First column (price0) - Min: {df['price0'].min()}")
    print(f"First column (price0) - Max: {df['price0'].max()}")
    print(f"Second column (price1) - Min: {df['price1'].min()}")
    print(f"Second column (price1) - Max: {df['price1'].max()}")

def create_scatter_plot(df):
    """Create a 2D scatter plot with percentile-based coloring for better color distribution"""
    plt.figure(figsize=(14, 10))
    
    # Use original p values from CSV
    p_values = analyze_original_p(df)
    
    # Convert coordinates to numeric for plotting
    price0_numeric = df['price0'].astype(float)
    price1_numeric = df['price1'].astype(float)
    
    # Create percentile-based coloring for better color distribution
    # This ensures colors are evenly distributed regardless of P value clustering
    p_percentiles = p_values.rank(pct=True) * 100  # Convert to percentile (0-100)
    
    print(f"\n=== PERCENTILE ANALYSIS ===")
    print(f"Percentile range: {p_percentiles.min():.2f} to {p_percentiles.max():.2f}")
    print(f"Percentile distribution:")
    for p in [10, 25, 50, 75, 90]:
        count = (p_percentiles <= p).sum()
        print(f"  {p}th percentile: {count} points")
    
    # Create scatter plot with percentile-based coloring
    scatter = plt.scatter(price0_numeric, price1_numeric, 
                         c=p_percentiles,  # Use percentiles instead of raw values
                         cmap='plasma',     # Plasma colormap for better contrast
                         s=30,             # Point size
                         alpha=0.7,        # Transparency for better visibility
                         edgecolors='black', # Black edges for definition
                         linewidth=0.5)
    
    # Add colorbar with percentile labels
    cbar = plt.colorbar(scatter, label='P Value Percentile', shrink=0.8)
    cbar.set_label('P Value Percentile (%)', size=12)
    
    # Add percentile tick marks to colorbar for better readability
    cbar.set_ticks([0, 25, 50, 75, 100])
    cbar.set_ticklabels(['0%', '25%', '50%', '75%', '100%'])
    
    plt.xlabel('price0', fontsize=12)
    plt.ylabel('price1', fontsize=12)
    plt.title(f'Price Points: price0 vs price1 (colored by P Value Percentile)\nTest Case: {test_case}', fontsize=14)
    
    # Add grid for better readability
    plt.grid(True, alpha=0.3)
    
    # Add interactive hover functionality for detailed point inspection
    def hover(event):
        if event.inaxes == plt.gca():
            # Find the closest point to mouse position
            x, y = event.xdata, event.ydata
            if x is not None and y is not None:
                # Calculate distances to all points
                distances = ((price0_numeric - x)**2 + (price1_numeric - y)**2)**0.5
                closest_idx = distances.idxmin()
                closest_p = p_values.iloc[closest_idx]
                closest_percentile = p_percentiles.iloc[closest_idx]
                closest_price0 = price0_numeric.iloc[closest_idx]
                closest_price1 = price1_numeric.iloc[closest_idx]
                
                # Update annotation with comprehensive point information
                annot.set_text(f'P: {closest_p:.6f}\nPercentile: {closest_percentile:.1f}%\nprice0: {closest_price0:.6f}\nprice1: {closest_price1:.6f}')
                annot.xy = (x, y)
                annot.set_visible(True)
                plt.draw()
            else:
                annot.set_visible(False)
                plt.draw()
    
    # Create annotation for hover display
    annot = plt.annotate("", xy=(0,0), xytext=(20,20), textcoords="offset points",
                         bbox=dict(boxstyle="round", fc="w", alpha=0.8),
                         arrowprops=dict(arrowstyle="->"))
    annot.set_visible(False)
    
    # Connect the hover event to the plot
    plt.connect('motion_notify_event', hover)
    
    plt.tight_layout()
    plt.show()

def create_3d_plot(df):
    """Create an interactive 3D scatter plot for exploring the data in 3D space"""
    fig = plt.figure(figsize=(16, 12))
    ax = fig.add_subplot(111, projection='3d')
    
    # Prepare data
    p_values = pd.to_numeric(df['p'], errors='coerce').astype(float)
    price0_numeric = df['price0'].astype(float)
    price1_numeric = df['price1'].astype(float)
    
    # Filter out points where price0 equals 1000000000000000000
    filter_mask = price0_numeric != 1000000000000000000
    p_values_filtered = p_values[filter_mask]
    price0_filtered = price0_numeric[filter_mask]
    price1_filtered = price1_numeric[filter_mask]
    
    print(f"\n=== 3D PLOT FILTERING ===")
    print(f"Original points: {len(p_values)}")
    print(f"Points after filtering price0 != 1000000000000000000: {len(p_values_filtered)}")
    print(f"Filtered out: {len(p_values) - len(p_values_filtered)} points")
    
    # Create 3D scatter plot with actual P values on Z-axis
    scatter = ax.scatter(price0_filtered, price1_filtered, p_values_filtered,  # Use actual P values for Z-axis
                        c=p_values_filtered,  # Color by actual P values, not percentiles
                        cmap='plasma',
                        s=20,
                        alpha=0.6,
                        edgecolors='black',
                        linewidth=0.3)
    
    # Add colorbar for actual P values
    cbar = plt.colorbar(scatter, ax=ax, shrink=0.8, aspect=20)
    cbar.set_label('P Value', size=12)
    
    # Set labels and title
    ax.set_xlabel('price0', fontsize=12)
    ax.set_ylabel('price1', fontsize=12)
    ax.set_zlabel('P Value', fontsize=12)
    ax.set_title(f'3D Price Points: price0 vs price1 vs P Value\nTest Case: {test_case} (Filtered)', fontsize=14)
    
    # Add grid for better orientation
    ax.grid(True, alpha=0.3)
    
    # Add interactive hover functionality for 3D plot
    def hover_3d(event):
        if event.inaxes == ax:
            # Get mouse position in 3D
            x, y = event.xdata, event.ydata
            if x is not None and y is not None:
                # For 3D, we need to find the closest point in 2D projection
                # This is a simplified approach - in practice you might want more sophisticated 3D picking
                distances = ((price0_filtered - x)**2 + (price1_filtered - y)**2)**0.5
                closest_idx = distances.idxmin()
                closest_p = p_values_filtered.iloc[closest_idx]
                closest_price0 = price0_filtered.iloc[closest_idx]
                closest_price1 = price1_filtered.iloc[closest_idx]
                
                # Update annotation
                annot_3d.set_text(f'P: {closest_p:.6f}\nprice0: {closest_price0:.6f}\nprice1: {closest_price1:.6f}')
                annot_3d.xy = (x, y)
                annot_3d.set_visible(True)
                plt.draw()
            else:
                annot_3d.set_visible(False)
                plt.draw()
    
    # Create annotation for 3D hover
    annot_3d = ax.annotate("", xy=(0,0), xytext=(20,20), textcoords="offset points",
                           bbox=dict(boxstyle="round", fc="w", alpha=0.8),
                           arrowprops=dict(arrowstyle="->"))
    annot_3d.set_visible(False)
    
    # Connect hover event
    plt.connect('motion_notify_event', hover_3d)
    
    plt.tight_layout()
    plt.show()

def create_percentile_plots(df):
    """Create additional analysis plots showing percentile distribution and discrete bins"""
    p_values = pd.to_numeric(df['p'], errors='coerce').astype(float)
    price0_numeric = df['price0'].astype(float)
    price1_numeric = df['price1'].astype(float)
    
    # Calculate percentiles for analysis
    p_percentiles = p_values.rank(pct=True) * 100
    
    # Create subplots for comprehensive analysis
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(16, 12))
    
    # 1. Histogram of raw P values to understand the original distribution
    ax1.hist(p_values, bins=50, alpha=0.7, color='skyblue', edgecolor='black')
    ax1.set_title('Distribution of P Values')
    ax1.set_xlabel('P Value')
    ax1.set_ylabel('Frequency')
    ax1.grid(True, alpha=0.3)
    
    # 2. Histogram of percentiles (should be uniform if ranking works correctly)
    ax2.hist(p_percentiles, bins=20, alpha=0.7, color='lightgreen', edgecolor='black')
    ax2.set_title('Distribution of P Value Percentiles')
    ax2.set_xlabel('Percentile (%)')
    ax2.set_ylabel('Frequency')
    ax2.grid(True, alpha=0.3)
    
    # 3. Scatter plot with percentile coloring for comparison
    scatter3 = ax3.scatter(price0_numeric, price1_numeric, c=p_percentiles, cmap='plasma', s=20)
    plt.colorbar(scatter3, ax=ax3, label='Percentile (%)')
    ax3.set_title('Price Points (Percentile coloring)')
    ax3.set_xlabel('price0')
    ax3.set_ylabel('price1')
    ax3.grid(True, alpha=0.3)
    
    # 4. Scatter plot with discrete percentile bins for categorical analysis
    # Create discrete percentile bins (0-20%, 20-40%, etc.)
    percentile_bins = pd.cut(p_percentiles, bins=5, labels=['0-20%', '20-40%', '40-60%', '60-80%', '80-100%'])
    colors = plt.cm.plasma(np.linspace(0, 1, 5))
    
    for i, bin_label in enumerate(['0-20%', '20-40%', '40-60%', '60-80%', '80-100%']):
        mask = percentile_bins == bin_label
        if mask.any():
            ax4.scatter(price0_numeric[mask], price1_numeric[mask], 
                       c=[colors[i]], label=bin_label, s=20, alpha=0.7)
    
    ax4.set_title('Price Points (Discrete Percentile Bins)')
    ax4.set_xlabel('price0')
    ax4.set_ylabel('price1')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.show()

def main():
    """Main function to run the oracle fuzzing analysis"""
    csv_file_path = "../simulations/out/oracle_results.csv"
    print("Reading oracle CSV data...")
    df = read_oracle_csv(csv_file_path)
    
    df_cleaned = remove_duplicates(df)
    analyze_coordinates(df_cleaned)
    
    # Create multiple visualization types for comprehensive analysis
    print("\n=== CREATING 2D SCATTER PLOT ===")
    create_scatter_plot(df_cleaned)
    
    print("\n=== CREATING 3D INTERACTIVE PLOT ===")
    create_3d_plot(df_cleaned)
    
    print("\n=== CREATING PERCENTILE ANALYSIS PLOTS ===")
    create_percentile_plots(df_cleaned)

if __name__ == "__main__":
    main()
