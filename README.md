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

**Overview** — the headline figure is **net worth**: everything in your accounts
and cash, less everything owed on your cards. It is today's position and does not
move with the month switcher, so paying a card bill leaves it unchanged — the
money shifts from one side to the other. Income and spending for the month being
browsed sit underneath it, labelled with which month that is.

**Bank accounts** — bank accounts and cash. Each has an opening balance, a colour
and a running balance. Accounts can be archived (keeps history) or deleted
(removes their transactions, with a confirmation that tells you how many).

**Transfers** — moving money between two of your own accounts, from the **+**
menu on Accounts or by swiping an account row right. Pick both ends and an
amount; the sheet shows what each balance becomes before you commit, and warns
when the source would go overdrawn. It is written as one transaction that debits
one account and credits the other, marked as a transfer so it stays out of income
and spending and leaves your net worth untouched — nothing was earned or spent,
the money is just somewhere else. Filtering by either account finds it.

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

**Budgets** (Settings → Budgets) — a spending cap or a savings target measured
over a repeating window. A budget holds no money of its own; it watches the
transactions that already exist and reports how much of the period's amount they
have used up.

- **Expense** budgets fill up as money goes out and are unwound by a refund;
  **savings** budgets fill up as money comes in. The switch at the top of the
  editor picks which.
- The amount is written as an amount *per* period — "₹500 / 2 weeks". The unit is
  a day, week, month or year, or a **custom** one-off window between two dates
  that never repeats. Repeating periods are measured from the start date, so one
  starting on the 31st lands on the 28th in February and back on the 31st in
  March rather than drifting earlier.
- What counts is one choice — all expenses, all income, both netted, or only the
  categories you tick — narrowed by the categories you exclude and, when any are
  ticked, by the accounts and cards the budget is tied to. Ticking no account
  counts every one of them.
- Transfers and card payments never count: they settle or relocate money that was
  already counted when it was spent. Nor does anything dated in the future — it
  is on the Upcoming list, and the money hasn't moved yet.
- Each row shows what has gone against the budget, what is left, how many days
  the period has to run, and a bar that turns red once an expense budget is
  overspent. Archiving a budget keeps it and its history; deleting one leaves
  every transaction untouched.

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
month's spend. Transfers and bill payments carry a transfer marker, name both
ends ("Cash → icici bank"),
and are shown in a neutral colour and left out of the list's totals — the
spending they settle is already listed, so counting them again would double up.
The header says how many rows were left out whenever any are.

**Data** (Settings → Import, Export & Backup)

- *CSV export* — `Date, Time, Title, Type, Amount, Currency, Account,
  Account Type, Credit Card, Transfer To, Category, Note, ID`, RFC 4180 quoted.
- *CSV import* — only `Date` and `Amount` are required. Accounts and categories
  named in the file are created if missing (account type is guessed from the name
  when the column is absent), rows whose `ID` already exists are skipped so
  re-importing an export is safe, and unparseable rows are reported by line number
  rather than failing the whole file. A `Credit Card` column charges the row to
  that card, creating it with no limit if it is new; a row naming both an account
  and a card is read as a bill payment, which is how an export round-trips. A row
  naming a `Transfer To` account is read as a transfer out of its `Account`. A row
  from an older export, whose `Account Type` is `credit` and which has no
  `Credit Card` column, comes in as a card rather than a bank account. Opening
  balances are not in a CSV, so a re-import into an empty app reproduces the
  movements but not the balances they started from — use a backup for that. Handles `1,234.56`, `₹1,234`, `(45.00)` and
  a leading `-`; a negative amount means an expense when there's no `Type` column.
- *Backup / restore* — one JSON file with accounts, credit cards, categories,
  recurring rules and transactions, relationships included. Backups written by
  older versions still restore. The format is at version 4; a file from a newer
  build is declined rather than read with pieces missing. Restore replaces everything after a
  confirmation that tells you what's in the file.
- *Erase all data* — wipes everything and puts the default categories back.

Each of these shows a percentage while it runs. The work is pinned to the main
actor — SwiftData's context can't leave it, and the progress it reports drives
view state — so it yields between chunks to let the ring redraw rather than
freezing the screen and jumping to done. The pinning is explicit: an `async`
function is not otherwise isolated to its caller's actor, and would run on a
background thread instead. Row-based
tasks count rows; the backup export counts its two whole-file steps and the erase
counts its phases, rather than inventing a finer number than it has.

The app's Documents folder is exposed in **Files → On My iPhone → ExpenseTracker**
and in Finder, so you can drop a CSV or backup in and pull exports out without
using the share sheet.

**Appearance** — System / Light / Dark, and a currency picker that only changes
formatting, never stored values.

## Layout

```
ExpenseTracker/
  App/         app entry and the model container
  Models/      Account, CreditCard, Category, Transaction, RecurringRule, Budget
               (SwiftData)
  Services/    CalculatorEngine, RecurrenceEngine, BillingCycle, CardPaymentService,
               TransferService, CSVService, BackupService, BudgetEngine, SeedData
  Theme/       palette, card style, currency and date formatting
  Views/       one file per screen, plus AddTransaction/ and Components/
Config/
  Info.plist   the keys Xcode can't generate (file sharing)
```

The Xcode project uses a synchronized file group, so new files added anywhere
under `ExpenseTracker/` are picked up without touching the project file.

## Not built yet

- Minimum-due amounts, interest and late fees on cards — the bill is always the
  full statement balance.
- Charts beyond the month's top-five breakdown; budget history for periods
  that have already closed.
- Automatic tracking / bank sync — deliberately out of scope.
