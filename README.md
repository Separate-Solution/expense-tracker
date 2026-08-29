# Expense Tracker

A minimal, dark-mode-first iOS expense tracker. SwiftUI + SwiftData, no accounts,
no network — everything stays on the device.

## Requirements

- Xcode 16 or newer (built and tested with Xcode 26.3)
- iOS 17.0+ on the device

## Running it on your iPhone

1. Open `ExpenseTracker.xcodeproj`.
2. Select the **ExpenseTracker** target → **Signing & Capabilities**.
3. Set **Team** to your own Apple ID (Xcode → Settings → Accounts → add your Apple ID
   if it isn't there). A free account is fine.
4. Change **Bundle Identifier** from `com.kasa.expensetracker` to
   something unique to you if Xcode complains it's taken.
5. Plug in your iPhone, pick it from the device menu, press ⌘R.
6. On the phone: **Settings → General → VPN & Device Management** → trust your
   developer certificate.

With a free Apple ID the app expires after 7 days and needs a re-run from Xcode.
A paid developer account extends that to a year.

## What's in it

**Bank accounts** — bank accounts and cash. Each has an opening balance, a colour
and a running balance. Accounts can be archived (keeps history) or deleted
(removes their transactions, with a confirmation that tells you how many).

**Credit cards** — their own section beside bank accounts, because credit works
the other way round: you spend borrowed money and settle up later. A card has a
name, a credit limit, the day its statement closes and the day the bill is due.

- Spending on a card raises what you owe and lowers the credit you have left,
  shown as a bar on the card's row. The month's **Spent** total counts the
  purchase when you make it, not when you pay the bill.
- The overview has a **Credit Cards** block: what the last closed statement left
  to pay, when it is due (counting down, and turning red inside three days or
  once overdue), and what has been spent since that statement closed.
- **Pay** clears the bill in one tap. Pick the bank account it comes out of and
  it is logged as a single payment that takes the money off the account and off
  the card at once. It is marked as a bill payment rather than an expense, so it
  never double-counts against the purchases it settles. Paying part of it is
  fine — the remainder stays due.
- A statement closing on the 25th covers the 26th of the previous month through
  the 25th of this one, and closes at the end of that day, so the 25th's own
  purchases are still on it. A cycle set to the 31st lands on the 28th in
  February and back on the 31st in March rather than drifting earlier.
- Accounts you had saved as the old "Credit Card" *type* are converted into real
  credit cards the first time you open this version, keeping their name, colour
  and full history. They start with no credit limit, and the cards list says so
  until you set one.

**Adding a transaction** — the floating **+** runs the three steps you asked for:

1. Type a name (Return or **Next** advances). Recent names appear as chips; tapping
   one reuses its category and jumps straight to the amount.
2. Pick a category, with **Expense / Income** as the two parents at the top.
   A **New** tile creates a category inline without leaving the flow.
3. Enter the amount on a calculator keypad — `+ − × ÷`, with `×`/`÷` taking
   precedence, a running total under the expression, and `=` to collapse it.
   Chips above the keypad set the date (past, today or future), what paid for it,
   repeat schedule and a note. The **paid with** chip offers bank accounts and
   credit cards in one list, and highlights itself when a card is chosen.

**Categories** — flat list per type, with emoji, colour and drag-to-reorder.
Hiding a category keeps its transactions labelled; deleting leaves them
"Uncategorized" rather than destroying them.

**Recurring & subscriptions** — daily/weekly/monthly/yearly with an every-N
interval and an optional end date. Occurrences post themselves on launch and
whenever the app comes to the foreground. Monthly rules are always measured from
the start date, so one starting on the 31st lands on the 28th in February and
back on the 31st in March instead of drifting earlier each month. A rule with a
past start date offers to backfill the occurrences you missed. Editing a rule
rewrites only occurrences that haven't posted yet; deleting a rule keeps the
history it already created.

**Transactions** — grouped by day with per-day totals, searchable across title,
note, category, account and card, and filterable by type, payment source and
category. Future-dated entries are marked **Upcoming** and kept out of the
month's spend. Bill payments carry a transfer marker and name the card they
settle.

**Data** (Settings → Import, Export & Backup)

- *CSV export* — `Date, Time, Title, Type, Amount, Currency, Account,
  Account Type, Credit Card, Category, Note, ID`, RFC 4180 quoted.
- *CSV import* — only `Date` and `Amount` are required. Accounts and categories
  named in the file are created if missing (account type is guessed from the name
  when the column is absent), rows whose `ID` already exists are skipped so
  re-importing an export is safe, and unparseable rows are reported by line number
  rather than failing the whole file. A `Credit Card` column charges the row to
  that card, creating it with no limit if it is new; a row naming both an account
  and a card is read as a bill payment, which is how an export round-trips. Handles `1,234.56`, `₹1,234`, `(45.00)` and
  a leading `-`; a negative amount means an expense when there's no `Type` column.
- *Backup / restore* — one JSON file with accounts, credit cards, categories,
  recurring rules and transactions, relationships included. Backups written by
  older versions still restore; everything credit cards added is optional. Restore replaces everything after a
  confirmation that tells you what's in the file.
- *Erase all data* — wipes everything and puts the default categories back.

The app's Documents folder is exposed in **Files → On My iPhone → ExpenseTracker**
and in Finder, so you can drop a CSV or backup in and pull exports out without
using the share sheet.

**Appearance** — System / Light / Dark, and a currency picker that only changes
formatting, never stored values.

## Layout

```
ExpenseTracker/
  App/         app entry and the model container
  Models/      Account, CreditCard, Category, Transaction, RecurringRule (SwiftData)
  Services/    CalculatorEngine, RecurrenceEngine, BillingCycle, CardPaymentService,
               CSVService, BackupService, SeedData
  Theme/       palette, card style, currency and date formatting
  Views/       one file per screen, plus AddTransaction/ and Components/
Config/
  Info.plist   the keys Xcode can't generate (file sharing)
```

The Xcode project uses a synchronized file group, so new files added anywhere
under `ExpenseTracker/` are picked up without touching the project file.

## Not built yet

- **Transfers between bank accounts.** Moving money between two of your own
  accounts still has to be logged as an expense on one and income on the other,
  which inflates both totals for the month. Credit card bill payments already
  work this way properly; ordinary transfers should follow.
- Minimum-due amounts, interest and late fees on cards — the bill is always the
  full statement balance.
- Budgets, per-category limits, charts beyond the month's top-five breakdown.
- Automatic tracking / bank sync — deliberately out of scope.
