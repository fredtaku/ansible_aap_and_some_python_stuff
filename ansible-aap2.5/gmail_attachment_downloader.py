#!/usr/bin/env python3
"""
Gmail Attachment Downloader
Downloads image attachments from the most recent Gmail email with a specific subject received in the last 10 minutes.
Default subject: "IBM wins"
"""

import imaplib
import email
from email.header import decode_header
import os
import sys
from datetime import datetime, timedelta
import getpass


def connect_to_gmail(email_address, password):
    """Connect to Gmail using IMAP."""
    try:
        mail = imaplib.IMAP4_SSL("imap.gmail.com")
        mail.login(email_address, password)
        return mail
    except imaplib.IMAP4.error as e:
        print(f"Login failed: {e}")
        print("Make sure you're using an App Password, not your regular Gmail password.")
        sys.exit(1)


def decode_subject(subject):
    """Decode email subject."""
    decoded_parts = decode_header(subject)
    decoded_subject = ""
    for part, encoding in decoded_parts:
        if isinstance(part, bytes):
            decoded_subject += part.decode(encoding or "utf-8")
        else:
            decoded_subject += part
    return decoded_subject


def download_attachments(mail, subject_filter):
    """Download image attachments from the most recent email matching the subject in the last 10 minutes."""
    mail.select("inbox")

    # Calculate time 10 minutes ago
    time_threshold = datetime.now() - timedelta(minutes=10)
    search_date = time_threshold.strftime("%d-%b-%Y")

    # Search for emails from today (IMAP doesn't support minute-level precision)
    status, messages = mail.search(None, f'SINCE {search_date}')

    if status != "OK":
        print("No emails found.")
        return

    email_ids = messages[0].split()

    if not email_ids:
        print(f"No emails found with subject '{subject_filter}' in the last 10 minutes.")
        return

    # Store matching emails with their dates
    matching_emails = []

    for email_id in email_ids:
        # Fetch the email
        status, msg_data = mail.fetch(email_id, "(RFC822)")

        if status != "OK":
            continue

        # Parse email
        msg = email.message_from_bytes(msg_data[0][1])

        # Get email date
        date_str = msg.get("Date")
        try:
            # Parse various date formats
            email_date = email.utils.parsedate_to_datetime(date_str)
            # Make it timezone-aware if it's not
            if email_date.tzinfo is None:
                email_date = email_date.replace(tzinfo=datetime.now().astimezone().tzinfo)

            # Check if email is within last 10 minutes
            # Convert to naive datetime for comparison
            email_date_naive = email_date.replace(tzinfo=None)
            if email_date_naive < time_threshold:
                continue
        except Exception as e:
            print(f"Could not parse date: {date_str}, error: {e}")
            continue

        # Check subject
        subject = msg.get("Subject", "")
        decoded_subject = decode_subject(subject)

        if subject_filter.lower() not in decoded_subject.lower():
            continue

        # Store matching email
        matching_emails.append({
            'msg': msg,
            'date': email_date_naive,
            'date_str': date_str,
            'subject': decoded_subject
        })

    if not matching_emails:
        print(f"\nNo emails found with subject '{subject_filter}' in the last 10 minutes.")
        return

    # Sort by date and get the most recent one
    matching_emails.sort(key=lambda x: x['date'], reverse=True)
    most_recent = matching_emails[0]

    print(f"\nFound {len(matching_emails)} matching email(s).")
    print(f"Processing most recent email: '{most_recent['subject']}'")
    print(f"Date: {most_recent['date_str']}")

    downloaded_count = 0

    # Process attachments from the most recent email only
    for part in most_recent['msg'].walk():
        if part.get_content_maintype() == "multipart":
            continue
        if part.get("Content-Disposition") is None:
            continue

        # Check if it's an image
        content_type = part.get_content_type()
        if not content_type.startswith('image/'):
            continue

        filename = part.get_filename()

        if filename:
            # Decode filename if necessary
            decoded_filename_parts = decode_header(filename)
            decoded_filename = ""
            for part_data, encoding in decoded_filename_parts:
                if isinstance(part_data, bytes):
                    decoded_filename += part_data.decode(encoding or "utf-8")
                else:
                    decoded_filename += part_data

            # Save attachment
            filepath = os.path.join(os.getcwd(), decoded_filename)

            # Check if file already exists
            if os.path.exists(filepath):
                base, extension = os.path.splitext(decoded_filename)
                counter = 1
                while os.path.exists(filepath):
                    filepath = os.path.join(os.getcwd(), f"{base}_{counter}{extension}")
                    counter += 1

            with open(filepath, "wb") as f:
                f.write(part.get_payload(decode=True))

            print(f"Downloaded: {filepath}")
            downloaded_count += 1

    if downloaded_count == 0:
        print(f"\nNo image attachments found in the most recent email.")
    else:
        print(f"\nTotal image attachments downloaded: {downloaded_count}")


def main():
    # Get credentials
    print("Gmail Attachment Downloader")
    print("-" * 40)

    default_email = "fredjjstar@gmail.com"
    email_input = input(f"Enter your Gmail address (default: {default_email}): ").strip()
    email_address = email_input if email_input else default_email

    # Get subject filter with default
    default_subject = "IBM wins"
    if len(sys.argv) >= 2:
        subject_filter = sys.argv[1]
    else:
        subject_input = input(f"Enter email subject (default: {default_subject}): ").strip()
        subject_filter = subject_input if subject_input else default_subject

    password = getpass.getpass("Enter your App Password: ")

    print("\nConnecting to Gmail...")
    mail = connect_to_gmail(email_address, password)
    print("Connected successfully!")

    print(f"\nSearching for emails with subject containing: '{subject_filter}'")
    print("Looking for emails from the last 10 minutes...")

    download_attachments(mail, subject_filter)

    mail.close()
    mail.logout()
    print("\nDone!")


if __name__ == "__main__":
    main()
