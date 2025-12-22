import json
import glob
import re
import pandas as pd
from dateutil import parser as date_parser
from datetime import timedelta

# Configuration
DATA_DIR = "/Users/anderson/Downloads/CMU Block Market/block-market_SrjTAhhODm/"
OUTPUT_CSV = "cmu_block_market_transactions.csv"

# Regex Patterns
RE_PRICE = re.compile(r'\b(\d+(\.\d+)?)\b')
RE_PAYMENT = re.compile(r'\b(venmo|zelle|v|z|vz|zv)\b', re.IGNORECASE)
RE_TYPE_GH = re.compile(r'\b(gh|grubhub)\b', re.IGNORECASE)
RE_TYPE_BLOCK = re.compile(r'\b(block|swipe)\b', re.IGNORECASE)
RE_TYPE_BLOCK_PLUS = re.compile(r'\b(block\s*\+?\s*1|b\s*\+?\s*1|flex)\b', re.IGNORECASE)

# New Regex Patterns
RE_QUANTITY_FOR = re.compile(r'(?:for|x|qty)\s*(\d+)', re.IGNORECASE)
RE_QUANTITY_PREFIX = re.compile(r'\b(\d+)\s*(?:blocks?|swipes?|ghs?)\b', re.IGNORECASE)
RE_PRICE_FOR_QUANTITY = re.compile(r'\b(\d+(?:\.\d+)?)\s*(?:for|4)\s*(\d+)\b', re.IGNORECASE)
RE_FLEX_AMOUNT = re.compile(r'\b(\d+(?:\.\d+)?)\s*(?:flex|f|dining|dd)\b', re.IGNORECASE)
RE_DONATION = re.compile(r'\b(donate|donating|donation|free|give\s*away|gift)\b', re.IGNORECASE)

RE_SELLER_INDICATOR = re.compile(r'\b(selling|wts|s>|have)\b', re.IGNORECASE)
RE_BUYER_INDICATOR = re.compile(r'\b(buying|wtb|b>|need|lf|looking for)\b', re.IGNORECASE)

def load_messages(data_dir):
    files = glob.glob(f"{data_dir}/block-market_page_*.json")
    all_messages = []
    print(f"Found {len(files)} files.")
    
    for fpath in files:
        try:
            with open(fpath, 'r') as f:
                data = json.load(f)
                # Ensure it's a list
                if isinstance(data, list):
                    all_messages.extend(data)
        except Exception as e:
            print(f"Error reading {fpath}: {e}")
            
    print(f"Total messages loaded: {len(all_messages)}")
    
    # Sort by timestamp
    # Add parsed datetime
    clean_messages = []
    for m in all_messages:
        if 'timestamp' in m and 'content' in m:
            try:
                m['dt'] = date_parser.parse(m['timestamp'])
                clean_messages.append(m)
            except:
                pass
                
    clean_messages.sort(key=lambda x: x['dt'])
    return clean_messages

def extract_order_info(content):
    content_lower = content.lower()
    
    # 0. Check for Donation
    is_donation = False
    if RE_DONATION.search(content_lower):
        is_donation = True
        
    # 1. Determine Type
    item_type = None
    if RE_TYPE_BLOCK_PLUS.search(content_lower):
        item_type = "block+1"
    elif RE_TYPE_GH.search(content_lower):
        item_type = "grubhub"
    elif RE_TYPE_BLOCK.search(content_lower):
        item_type = "block"
        
    # 1b. Check for Flex amount
    flex_amount = 0.0
    flex_match = RE_FLEX_AMOUNT.search(content_lower)
    if flex_match:
        flex_amount = float(flex_match.group(1))
        # If item_type was not found but flex was, maybe it's a flex order?
        if not item_type:
            item_type = "flex_only"
        elif item_type == "block":
            item_type = "block+flex"

    if not item_type and not is_donation:
        return None # Not an order
        
    # 2. Determine Quantity & Price
    quantity = 1
    price = None
    
    # Check for specific "X for Y" pattern first (e.g. "17 for 2")
    price_qty_match = RE_PRICE_FOR_QUANTITY.search(content_lower)
    if price_qty_match:
        val1 = float(price_qty_match.group(1))
        val2 = float(price_qty_match.group(2))
        
        # Heuristic: Price is usually higher than quantity, unless huge quantity
        # Price usually > 1.5. Quantity usually integer < 10.
        if val1 > val2 and val2 < 10:
            price = val1
            quantity = int(val2)
        elif val2 > val1 and val1 < 10:
            price = val2
            quantity = int(val1)
            
    # If not found, look for quantity separately
    if quantity == 1:
        qty_match = RE_QUANTITY_PREFIX.search(content_lower)
        if qty_match:
            quantity = int(qty_match.group(1))
        else:
            qty_match_for = RE_QUANTITY_FOR.search(content_lower)
            if qty_match_for:
                quantity = int(qty_match_for.group(1))

    # If price still not found
    if price is None:
        if is_donation:
            price = 0.0
        else:
            numbers = [float(x[0]) for x in RE_PRICE.findall(content_lower)]
            
            # Filter valid prices
            possible_prices = []
            for n in numbers:
                # Exclude quantity if we found it
                if n == quantity:
                    continue
                # Exclude flex amount
                if n == flex_amount:
                    continue
                    
                if 1.5 <= n <= 50: # Reasonable price range
                    possible_prices.append(n)
            
            if possible_prices:
                price = max(possible_prices)
    
    # Validation for Quantity > 2 (Max allowed is 2)
    # If quantity > 2, it's likely a misinterpretation of price or invalid.
    if quantity > 2 and not is_donation:
        # If we have no price, but quantity looks like a price, swap.
        # e.g. "selling 5 blocks" -> parsed as qty=5. Likely price=5, qty=1.
        if (price is None or price == 0) and 1.5 <= quantity <= 50:
            price = float(quantity)
            quantity = 1
        else:
            # If we strictly cannot have > 2, and it's not a price swap situation:
            # Maybe mark it as None (invalid order) or cap it?
            # Given the user rule "only a maximum of 2 blocks can be sold at once", 
            # we should treat > 2 as suspicious. 
            # If price exists (e.g. "17 for 3"), it breaks the rule.
            return None 

    if price is None and not is_donation:
        return None # No valid price found
        
    # 3. Determine Payment
    payment = "unknown"
    matches = RE_PAYMENT.findall(content_lower)
    if matches:
        unique_matches = set([m.lower() for m in matches])
        clean_matches = set()
        for m in unique_matches:
            if m in ['v', 'venmo']: clean_matches.add('venmo')
            if m in ['z', 'zelle']: clean_matches.add('zelle')
            if m in ['vz', 'zv']: 
                clean_matches.add('venmo')
                clean_matches.add('zelle')
        payment = "/".join(sorted(list(clean_matches)))
        
    # 4. Determine Direction (Buy/Sell)
    direction = "buy" # Default
    if is_donation:
        direction = "sell" # Donating is selling for $0
    elif RE_SELLER_INDICATOR.search(content_lower):
        direction = "sell"
    elif RE_BUYER_INDICATOR.search(content_lower):
        direction = "buy"
    else:
        pass
        
    return {
        "item": item_type,
        "price": price,
        "quantity": quantity,
        "flex_amount": flex_amount,
        "is_donation": is_donation,
        "payment": payment,
        "direction": direction
    }

def is_troll(order_info, content):
    if not order_info: return False
    
    price = order_info['price']
    
    # Price Heuristics (Skip for donations)
    if not order_info['is_donation']:
        if price > 60: return True 
        # Price < 1.5 handled in extraction (returns None), 
        # but if we forced a match via "X for Y", check again.
        if price < 1.0 and price > 0: return True 
    
    # Text Heuristics
    bad_words = ['feet', 'pic', 'soul', 'kidney', 'scam', 'joke']
    if any(w in content.lower() for w in bad_words):
        return True
        
    return False

def match_transactions(messages):
    transactions = []
    active_orders = [] # List of (msg_obj, order_info)
    order_map = {} # Map msg_id -> order_info for quick reply lookup
    
    # Window for matching: e.g., 15 minutes
    MATCH_WINDOW = timedelta(minutes=15)
    RE_BUMP = re.compile(r'^\s*bump(?:\s+to)?\s*(\d+(\.\d+)?)\b', re.IGNORECASE)
    
    for msg in messages:
        content = msg.get('content', '')
        author = msg.get('author', {}).get('username', 'unknown')
        msg_time = msg['dt']
        msg_id = msg.get('id')
        
        # 0. Check for Bump (Update active order)
        bump_match = RE_BUMP.search(content)
        if bump_match:
            new_price = float(bump_match.group(1))
            # Find user's last order to update
            for i in range(len(active_orders) - 1, -1, -1):
                prev_msg, prev_info = active_orders[i]
                if prev_msg.get('author', {}).get('username') == author:
                    # Found own previous order. Update price.
                    # Create updated info
                    updated_info = prev_info.copy()
                    updated_info['price'] = new_price
                    
                    # Remove old order
                    del active_orders[i]
                    
                    # Add new order (refreshes timestamp)
                    active_orders.append((msg, updated_info))
                    if msg_id:
                        order_map[msg_id] = updated_info # Track bump as the active order
                    
                    # Do not treat as a new order extraction or response
                    continue

        # 1. Is this an Order?
        order_info = extract_order_info(content)
        is_troll_order = is_troll(order_info, content)
        
        if order_info and not is_troll_order:
            # It's a valid order listing. Add to active.
            # Expire old orders
            active_orders = [x for x in active_orders if msg_time - x[0]['dt'] < MATCH_WINDOW]
            active_orders.append((msg, order_info))
            if msg_id:
                order_map[msg_id] = order_info
            
        # 2. Is this a Response?
        is_response = False
        target_msg = None
        target_info = None
        
        # 2a. Check Explicit Reply first
        if 'referenced_message' in msg and msg['referenced_message']:
            ref = msg['referenced_message']
            ref_id = ref.get('id')
            # Look up if the referenced message was an order
            # Note: We might need to look up in active_orders or just keep a global map of recent orders.
            # For simplicity, let's look in active_orders + check if ref text looks like order.
            
            # Check if ref_id is in our tracked active orders
            # (Limitation: active_orders gets pruned, but replies might be to older msgs. 
            # But the 15min window is strict for "active" market anyway.)
            
            # Try to find match in active orders by ID (if we tracked IDs there) or just check text
            # Better: Parse the referenced content on the fly if needed.
            ref_content = ref.get('content', '')
            ref_info = extract_order_info(ref_content)
            
            if ref_info and not is_troll(ref_info, ref_content):
                # Valid Reply Match!
                # FILTER: Ensure reply is a transaction confirmation, not just chatter/question.
                is_valid_reply = False
                lower_reply = content.lower()
                
                # 1. Keywords
                if re.search(r'\b(dm|pm|messaged|check|dmed|pmed|sent|claim|sold|take|gotchu|mine|interested)\b', lower_reply):
                    is_valid_reply = True
                
                # 2. Short length (likely "Me", "I will", "Here")
                elif len(content) < 15:
                    is_valid_reply = True
                
                # 3. Exclude Questions (Clarifications)
                if "?" in content:
                    is_valid_reply = False
                
                # 4. Strict "Omg" / Chatter filter
                # e.g., "Omg hi cadence" is just chatter. 
                # If short length triggered it, but it starts with 'omg' or 'lol' or 'lmao', discard.
                if re.match(r'^(omg|lol|lmao|haha)', lower_reply):
                    is_valid_reply = False
                    
                if is_valid_reply:
                    target_msg = ref
                    target_info = ref_info
                    is_response = True
        
        # 2b. Implicit "DM" / Proximity Match (Only if not already matched via Reply)
        if not is_response:
            lower_content = content.lower()
            # Strict chatter filter: Must contain response keywords AND be short
            if re.search(r'\b(dm|pm|messaged|check|dmed|pmed|sent)\b', lower_content) and len(lower_content) < 50:
                is_response = True
                
        if is_response:
            # If we have an explicit target, use it.
            # If not, find implicit target from active_orders.
            
            match_found = False
            target_author = None # Initialize
            
            if target_msg and target_info:
                # Explicit Reply Logic
                 target_author = target_msg.get('author', {}).get('username')
                 if target_author != author:
                     match_found = True
            elif active_orders:
                # Implicit Match Logic
                for i in range(len(active_orders) - 1, -1, -1):
                    cand_msg, cand_info = active_orders[i]
                    cand_author = cand_msg.get('author', {}).get('username')
                    if cand_author != author:
                        target_msg = cand_msg
                        target_info = cand_info
                        target_author = cand_author # Capture here
                        match_found = True
                        # Clean up
                        del active_orders[i]
                        break
            
            if match_found:
                 # Re-extract author safely if needed
                 if not target_author:
                     target_author = target_msg.get('author', {}).get('username')

                 buyer = target_author if target_info['direction'] == 'buy' else author
                 seller = author if target_info['direction'] == 'buy' else target_author
                 
                 transactions.append({
                     "timestamp": msg_time,
                     "buyer": buyer,
                     "seller": seller,
                     "item": target_info['item'],
                     "price": target_info['price'],
                     "quantity": target_info['quantity'],
                     "flex_amount": target_info['flex_amount'],
                     "is_donation": target_info['is_donation'],
                     "payment": target_info['payment'],
                     "original_order_text": target_msg.get('content'),
                     "response_text": content,
                     "match_type": "reply" if 'referenced_message' in msg and msg['referenced_message'] else "proximity"
                 })

    return transactions

def main():
    print("Loading messages...")
    messages = load_messages(DATA_DIR)
    print("Processing transactions...")
    transactions = match_transactions(messages)
    
    print(f"Found {len(transactions)} transactions.")
    
    # Save to CSV
    df = pd.DataFrame(transactions)
    df.to_csv(OUTPUT_CSV, index=False)
    print(f"Saved to {OUTPUT_CSV}")

if __name__ == "__main__":
    main()
