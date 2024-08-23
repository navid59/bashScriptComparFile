#!/bin/bash

# Constants (can change "RON" to "USD" or "EURO" as needed)
TARGET_CURRENCY="RON"

# Input and output files
FILE1="./Src/NavidWorkSpace_Sanitied_RON.csv"
FILE2="./Src/FisierPlatform_SoldFinal.csv"
SUCCESS_FILE="./Output/success.csv"
MISMATCH_FILE="./Output/mismatch.csv"
ERROR_FILE="./Output/error.csv"
DUPLICATE_FILE="./Output/duplicate.csv"
INVALID_NUM_FILE="./Output/invalid_numbers.csv"
REPORT_FILE="./Output/report.csv"

# Clean up any previous output files
> "$SUCCESS_FILE"
> "$MISMATCH_FILE"
> "$ERROR_FILE"
> "$DUPLICATE_FILE"
> "$INVALID_NUM_FILE"
> "$REPORT_FILE"

# Add headers to the output files
echo "Partener,CodFiscal,SoldCredit,Sold_final,Currency" >> "$SUCCESS_FILE"
echo "Partener,CodFiscal,SoldCredit,Sold_final,Currency" >> "$MISMATCH_FILE"
echo "Partener,CodFiscal,SoldCredit,Sold_final,Currency" >> "$DUPLICATE_FILE"
echo "TypeFile,Partener,CodFiscal,SoldCredit,Sold_final,Currency" >> "$INVALID_NUM_FILE"
echo "Description" >> "$REPORT_FILE"

# Function to check if a value is a valid number
is_valid_number() {
    local value="$1"
    [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
}


# Function to calculate the sum of Sold_final values
calculate_sum() {
    local matching_lines="$1"
    local sum=0
    while IFS=',' read -r Type An Luna Moneda cmpid Partener CUI Sold_final; do
        if is_valid_number "$Sold_final"; then
            sum=$(echo "$sum + $Sold_final" | bc)
        fi
    done <<< "$matching_lines"
    echo "$sum"
}

# Skip the header of the first file
tail -n +2 "$FILE1" | while IFS=',' read -r  Cont CodFiscal DenumirePartener SoldCredit; do

    # Trim spaces from CodFiscal (if any)
    CodFiscal=$(echo "$CodFiscal" | tr -d '[:space:]')

    # Clean and trim DenumirePartener, remove double quotes, etc.
    # DenumirePartener=$(echo "$DenumirePartener" | tr -d '[:space:]' | tr -d '"')

    # If CodFiscal is empty, log an error and continue to the next record
    if [[ -z "$CodFiscal" ]]; then
        echo "Error: Missing CodFiscal for record with DenumirePartener: $DenumirePartener" >> "$ERROR_FILE"
        continue
    fi

    # Check if SoldCredit is a valid number
    if ! is_valid_number "$SoldCredit"; then
        echo "BadSoldCreadit,$DenumirePartener,$CodFiscal,$SoldCredit,N/A,$TARGET_CURRENCY" >> "$INVALID_NUM_FILE"
        continue
    fi

    # Perform a direct grep on the second file to check for CodFiscal presence
    if ! grep -q "$CodFiscal" "$FILE2"; then
        echo "Error: No matching CodFiscal ($CodFiscal) found in the second file (grep check)." >> "$ERROR_FILE"
        continue
    fi

    # Find matching lines in the second file with the same CodFiscal and Moneda = TARGET_CURRENCY
    MATCHING_LINES=$(awk -F',' -v currency="$TARGET_CURRENCY" -v codfiscal="$CodFiscal" '
        $7 == codfiscal && $4 == currency {
            print $0
        }
    ' "$FILE2")

    if [[ -z "$MATCHING_LINES" ]]; then
        echo "Error: No matching CodFiscal ($CodFiscal) found in the second file (awk check)." >> "$ERROR_FILE"
        continue
    fi

    # Check if there are duplicate entries
    MATCH_COUNT=$(echo "$MATCHING_LINES" | wc -l)
    if [[ "$MATCH_COUNT" -gt 1 ]]; then
        # Calculate the sum of Sold_final
        SUM_SOLD_FINAL=$(calculate_sum "$MATCHING_LINES")
        
        # Compare the sum with SoldCredit
        if [[ "$SUM_SOLD_FINAL" == "$SoldCredit" ]]; then
            echo "$DenumirePartener,$CodFiscal,$SoldCredit,$SUM_SOLD_FINAL,$TARGET_CURRENCY" >> "$SUCCESS_FILE"
        else
            # Log to the report file with the calculation details
            echo "$DenumirePartener,$CodFiscal,$SoldCredit,$SUM_SOLD_FINAL,$TARGET_CURRENCY" >> "$MISMATCH_FILE"
            # Create a detailed report
            echo "Mismatch for CodFiscal: $CodFiscal - SoldCredit: $SoldCredit, Sum of Sold_final: $SUM_SOLD_FINAL" >> "$REPORT_FILE"
        fi
        
        continue
    fi

    # Loop over the matching lines (only one in this case)
    echo "$MATCHING_LINES" | while IFS=',' read -r Type An Luna Moneda cmpid Partener CUI Sold_final; do

        # Clean Partener and remove any double quotes
        Partener=$(echo "$Partener" | tr -d '"')

        # Check if Sold_final is a valid number
        if ! is_valid_number "$Sold_final"; then
            echo "BadSoldFinal,$DenumirePartener,$CodFiscal,$SoldCredit,$Sold_final,$Moneda" >> "$INVALID_NUM_FILE"
            continue
        fi

        # Compare SoldCredit with Sold_final
        if [[ "$SoldCredit" == "$Sold_final" ]]; then
            echo "$DenumirePartener,$CodFiscal,$SoldCredit,$Sold_final,$Moneda" >> "$SUCCESS_FILE"
        else
            echo "$DenumirePartener,$CodFiscal,$SoldCredit,$Sold_final,$Moneda" >> "$MISMATCH_FILE"
        fi

    done

done
