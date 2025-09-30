# Remind module for Nushell
# Send delayed notifications using background jobs
#
# ⚠️  EXPERIMENTAL: Uses Nushell's experimental `job spawn` feature.
# Recommended primarily for macOS with native notification support.
# Linux and other platforms may have limited notification capabilities.

const REMIND_VERSION = "0.1.0"

# Initialize reminders storage
def --env init-reminders [] {
  if not ("AMASIA_REMINDERS" in $env) {
    $env.AMASIA_REMINDERS = []
  }
}

# Parse time string (5min, 1h, 30s) to seconds
def parse-duration [time: string]: nothing -> int {
  let time_lower = ($time | str downcase)

  if ($time_lower | str ends-with 's') {
    $time_lower | str replace 's' '' | into int
  } else if ($time_lower | str ends-with 'min') {
    let mins = ($time_lower | str replace 'min' '' | into int)
    $mins * 60
  } else if ($time_lower | str ends-with 'm') {
    let mins = ($time_lower | str replace 'm' '' | into int)
    $mins * 60
  } else if ($time_lower | str ends-with 'h') {
    let hours = ($time_lower | str replace 'h' '' | into int)
    $hours * 3600
  } else {
    # Assume seconds if no suffix
    $time | into int
  }
}

# Parse time string (HH:MM) and calculate seconds until that time
def parse-time-of-day [time_str: string]: nothing -> int {
  let parts = ($time_str | split row ':')
  let hour = ($parts | get 0 | into int)
  let minute = ($parts | get 1 | into int)

  let now = (date now)
  let target = ($now | format date '%Y-%m-%d') ++ $' ($time_str):00'
  let target_date = ($target | into datetime)

  # If target time is in the past, add 1 day
  let target_final = (if ($target_date < $now) {
    $target_date + 1day
  } else {
    $target_date
  })

  ($target_final - $now) / 1sec | math round
}

# Send system notification (platform-specific)
def send-notification [message: string, title: string = "Reminder"] {
  let host = (sys host)
  let os = ($host | get name)
  let os_long = ($host | get long_os_version)

  if ($os == "Darwin") {
    # macOS
    ^osascript -e $'display notification "($message)" with title "($title)"'
  } else if ($os_long | str starts-with "Linux") {
    # Linux - try notify-send if available
    let has_notify = (which notify-send | is-not-empty)
    if $has_notify {
      try {
        ^notify-send $title $message
      } catch {
        # notify-send failed (no D-Bus/desktop), fallback to terminal
        print $"(ansi yellow_bold)($title)(ansi reset): ($message)"
      }
    } else {
      # No notify-send, use terminal
      print $"(ansi yellow_bold)($title)(ansi reset): ($message)"
    }
  } else {
    # Fallback: colored text
    print $"(ansi yellow_bold)($title)(ansi reset): ($message)"
  }
}


# Set a reminder after specified duration
export def --env in [
  time: string    # Time to wait (e.g., "5min", "1h", "30s")
  message: string # Reminder message
  --title: string = "Reminder" # Notification title
] {
  init-reminders

  let seconds = (parse-duration $time)
  let now = (date now)
  let trigger_at = ($now + ($seconds * 1sec))

  # Create reminder record
  let reminder_id = (if ($env.AMASIA_REMINDERS | is-empty) { 1 } else {
    ($env.AMASIA_REMINDERS | get id | math max) + 1
  })

  print $" Reminder set for ($time): ($message)"

  # Launch background job
  let duration = ($seconds * 1sec)
  let msg = $message
  let ttl = $title

  let job_id = (job spawn {||
    sleep $duration
    send-notification $msg $ttl
  })

  # Store reminder
  $env.AMASIA_REMINDERS = ($env.AMASIA_REMINDERS | append {
    id: $reminder_id
    type: "in"
    time: $time
    message: $message
    title: $title
    created_at: $now
    trigger_at: $trigger_at
    job_id: $job_id
  })
}

# Set a reminder at specific time
export def --env at [
  time: string    # Time in HH:MM format (e.g., "20:35")
  message: string # Reminder message
  --title: string = "Reminder" # Notification title
] {
  init-reminders

  let seconds = (parse-time-of-day $time)
  let now = (date now)
  let trigger_at = ($now + ($seconds * 1sec))

  # Create reminder record
  let reminder_id = (if ($env.AMASIA_REMINDERS | is-empty) { 1 } else {
    ($env.AMASIA_REMINDERS | get id | math max) + 1
  })

  print $" Reminder set for ($time): ($message)"

  # Launch background job
  let duration = ($seconds * 1sec)
  let msg = $message
  let ttl = $title

  let job_id = (job spawn {||
    sleep $duration
    send-notification $msg $ttl
  })

  # Store reminder
  $env.AMASIA_REMINDERS = ($env.AMASIA_REMINDERS | append {
    id: $reminder_id
    type: "at"
    time: $time
    message: $message
    title: $title
    created_at: $now
    trigger_at: $trigger_at
    job_id: $job_id
  })
}

# List all reminders (past and upcoming)
#
# ⚠️  EXPERIMENTAL: Uses Nushell's experimental `job spawn`.
# Recommended for macOS with native notifications.
#
# Usage:
#   remind in 5min "Coffee!"        # Set duration-based reminder
#   remind at 14:30 "Meeting"       # Set time-based reminder
#   remind                          # List all reminders
export def --env main [
  --version(-v)  # Show version
] {
  # Handle --version flag
  if $version {
    print $"($REMIND_VERSION)"
    return
  }

  init-reminders

  if ($env.AMASIA_REMINDERS | is-empty) {
    print "No reminders set."
    return
  }

  let now = (date now)

  # Split into past and upcoming based on trigger time
  let past = ($env.AMASIA_REMINDERS | where trigger_at < $now)
  let upcoming = ($env.AMASIA_REMINDERS | where trigger_at >= $now)

  if (not ($upcoming | is-empty)) {
    print $"(ansi green_bold)Upcoming reminders:(ansi reset)"
    $upcoming | sort-by trigger_at | select id type time message trigger_at | print
  }

  if (not ($past | is-empty)) {
    print $"\n(ansi default_dimmed)Past reminders:(ansi reset)"
    $past | sort-by trigger_at --reverse | select id type time message trigger_at | print
  }
}