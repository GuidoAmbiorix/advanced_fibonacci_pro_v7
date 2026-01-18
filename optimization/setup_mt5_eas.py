"""
Helper script to copy EAs to MT5 MQL5/Experts folder
This is required because MT5 Strategy Tester only works with EAs in its own folder
"""
import os
import shutil
from pathlib import Path


def find_mt5_experts_folder():
    """Find MT5 MQL5/Experts folder"""
    mt5_base = Path("C:/Program Files/MetaTrader 5")
    
    if not mt5_base.exists():
        return None
    
    # Standard location
    experts = mt5_base / "MQL5" / "Experts"
    if experts.exists():
        return experts
    
    return None


def copy_ea_to_mt5(source_path, ea_name=None):
    """
    Copy EA file to MT5 Experts folder
    
    Args:
        source_path: Path to source .mq5 file
        ea_name: Optional custom name (default: use original name)
    
    Returns:
        Path to EA in MT5 folder
    """
    source = Path(source_path)
    if not source.exists():
        raise FileNotFoundError(f"Source EA not found: {source}")
    
    experts_folder = find_mt5_experts_folder()
    if not experts_folder:
        raise FileNotFoundError("MT5 MQL5/Experts folder not found")
    
    # Use custom name or original
    dest_name = ea_name if ea_name else source.name
    dest_path = experts_folder / dest_name
    
    # Copy file
    shutil.copy2(source, dest_path)
    print(f"✅ Copied {source.name} to {dest_path}")
    
    return str(dest_path)


def copy_all_eas_from_folder(source_folder):
    """Copy all .mq5 files from folder to MT5 Experts"""
    source_dir = Path(source_folder)
    experts_folder = find_mt5_experts_folder()
    
    if not experts_folder:
        raise FileNotFoundError("MT5 MQL5/Experts folder not found")
    
    mq5_files = list(source_dir.glob("*.mq5"))
    
    print(f"\n📁 Copying {len(mq5_files)} EAs to MT5...")
    
    for mq5_file in mq5_files:
        dest = experts_folder / mq5_file.name
        shutil.copy2(mq5_file, dest)
        print(f"  ✅ {mq5_file.name}")
    
    print(f"\n✅ All EAs copied to: {experts_folder}")
    return experts_folder


if __name__ == "__main__":
    # Copy all EAs from data/ea_sources to MT5
    source_folder = Path(__file__).parent / "data" / "ea_sources"
    
    if source_folder.exists():
        experts_folder = copy_all_eas_from_folder(source_folder)
        print(f"\n📝 Note: MT5 can now access these EAs for backtesting")
        print(f"   Use paths like: {experts_folder / 'YourEA.mq5'}")
    else:
        print(f"❌ Source folder not found: {source_folder}")
