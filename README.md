# MedBillings

Medical inventory & billing for a retail pharmacy. Flutter desktop app for **Windows, macOS and Linux**. Everything is stored locally on the computer.

Bundle / application id: `com.developerstring.medical`

## Features

- **New Bill** (F2), built for the keyboard. Type a medicine, pick a batch, enter the quantity, press Enter.
  - The Medicine field suggests from inventory: stock, MRP, Rx badge, rack.
  - The Batch field suggests only in-stock, unexpired batches of that medicine, earliest expiry first (FEFO). If you type a batch that isn't sellable, you get a clear error: it doesn't exist, it's expired, or it's sold out.
  - Loose sale: `5` = 5 tablets, `2s` = 2 strips. Stock is tracked in units, e.g. "9 Strip + 5 Tab".
  - Antibiotic and Schedule H/H1/X items show their warning, and the bill can't be saved without a doctor.
  - The default doctor is pre-filled on every bill. Visiting doctors can still be typed in.
  - Patient and doctor suggestions come from past bills. Credit customers show a **Credit · ₹ due** badge.
  - Payment: Cash / UPI / Card / Credit (with an optional part-payment).
  - **Templates**: type a template number (F4), e.g. a saline kit. Batches are picked from current stock and every line stays editable on that bill.
  - **Save & Print** (F9 / Ctrl+P) prints the customer copy. Ctrl+S saves only.
- **Medical copy**: every bill is saved as a `.mbill` file (`Bills/yyyy/MM/`). The format is gzip-compressed JSON with a checksum, usually under 1 KB per bill. Open any `.mbill` from Bills → *Open bill file*, then view, reprint or export it as PDF.
- **Bills**: search by bill number, patient, doctor or medicine. Cancelling a bill returns its stock.
- **Credit**: customer profiles with outstanding balance and limit, a ledger of credit bills and payments with a running balance, and payment collection.
- **Inventory**: medicines, batches, opening stock, stock adjustment, and full stock history.
  Stock is always counted in strips + loose tablets. A medicine can optionally also come in boxes
  (e.g. 10 strips per box); boxes then show only where they matter: stock entry, packing details,
  billing's quantity selector ("1b" = one box), and expiry, which flags full boxes about to expire.
- **Stock Entry**: wholesaler invoices, one line per batch. Press **Enter** to move field to field; a complete
  Mfg (`725` → 07/25) jumps to Expiry and a complete Expiry jumps to Qty; Enter on Disc adds the line.
  Mfg and Expiry are required. "Tabs in Strip" comes from the medicine (read-only). For medicines that come
  in boxes, Qty, Free, Rate and MRP each have a Strip ⇄ Box switch (e.g. 10 Box + 1 Strip free, rate per box);
  everything is stored per strip. Batch numbers are capitalised as you type; GST accepts any rate.
- **Typed dates auto-format**: `724` → `07/24` for expiry/mfg, `24092026` → `24/09/2026` for invoice dates.
- **Expiry**: a pop-up every day while anything is within 60 days (configurable). Batches can be returned to the supplier, disposed, discounted for clearance, or marked as checked.
- **Suppliers**, **Doctors & Patients** (★ marks the default doctor), and a **Stock Ledger** of every entry and exit.
- **Dashboard**: today's and this month's sales, daily and monthly charts, expiries handled, low stock, top medicines.
- **GST is optional** (Settings → Billing → "GST registered"; off by default, as small shops needn't register).
  Off: bills are *Cash Memo* / *Credit Memo* showing just the **Total amount**, and GST fields are hidden in
  medicines, batches and stock entry. On: bills are *Tax Invoices* with GSTIN, HSN, **Taxable amount**,
  CGST/SGST at each rate, **Total GST** and **Net amount payable**. New medicines default to 5% GST.
- **Printing**: A4, A5 or 80 mm thermal, straight to the chosen printer.
- **Data**: full backup and restore (`.mbak`), CSV export of stock, bills and item-wise sales, and CSV import of the medicine list.

## Data location

`Documents/MedBillings/` holds `data/medbillings.db`, `Bills/` and `Backups/`.
Set `MEDBILLINGS_DATA_DIR` to use a different folder.

## Build & run

```bash
flutter pub get
flutter run -d macos      # or windows / linux
flutter build windows     # release build: build/windows/x64/runner/Release/MedBillings.exe
flutter build macos
flutter build linux
```

- Windows needs Visual Studio with "Desktop development with C++".
- Linux needs `clang cmake ninja-build pkg-config libgtk-3-dev`, plus `libcups2-dev` for printing.

## Tests

```bash
flutter test                                   # logic, file format
flutter test integration_test/billing_flow_test.dart -d macos   # drives the real billing screen
flutter test integration_test/stock_entry_test.dart -d macos   # stock entry, templates, medicine/supplier/credit forms
```

Run the integration files one at a time. They open the app window on your current desktop,
always on top at 1440×900, because macOS stops drawing windows that are off screen and the
tests would otherwise wait forever.

## Keyboard

| Key | Action |
| --- | --- |
| F1 / F2 | Dashboard / New bill |
| F3 / F4 | Medicine search / Template number |
| F6 / F7 | Patient / Doctor |
| Enter | Accept suggestion / move to the next field — in every form (bills, stock entry, medicines, batches, templates, suppliers, doctors, credit customers & payments, expiry actions, settings). Enter on the last field saves. On a bill: Patient → Mobile → Address → Doctor → Reg. no → Clinic → Medical details → Medicine → Batch → Qty → Disc (adds the line). Enter on an empty Medicine goes to Extra discount → Cash received / Paid now → Save & Print |
| F9, Ctrl+P | Save & print |
| Ctrl+S | Save |
| Ctrl+N | New bill |
