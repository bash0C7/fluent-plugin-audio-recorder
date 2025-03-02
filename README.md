# fluent-plugin-audio-recorder

[Fluentd](https://fluentd.org/) input plugin for recording audio from macOS devices.

This plugin allows you to record audio from macOS devices with automatic silence detection for stopping recordings. It uses FFmpeg with avfoundation to capture audio and can be configured with various audio parameters. When a silence period is detected or the plugin is shut down, it writes the recording to a file, includes the binary data in the record, and emits an event.

## Installation

### RubyGems

```
$ gem install fluent-plugin-audio-recorder
```

### Bundler

Add following line to your Gemfile:

```ruby
gem "fluent-plugin-audio-recorder"
```

And then execute:

```
$ bundle
```

## Configuration

```
<source>
  @type audio_recorder
  
  # Required parameters
  device 0                # Recording device number (integer)
  
  # Optional parameters
  silence_duration 1.0    # Duration in seconds to consider as silence (default: 1.0)
  noise_level -30         # Noise level threshold in dB for silence detection (default: -30)
  min_duration 2          # Minimum recording duration in seconds (default: 2)
  max_duration 900        # Maximum recording duration in seconds (default: 900 = 15 minutes)
  
  # Audio settings
  audio_codec aac         # Audio codec (default: aac)
  audio_bitrate 192k      # Audio bitrate (default: 192k)
  audio_sample_rate 44100 # Audio sample rate (default: 44100)
  audio_channels 1        # Audio channels (default: 1)
  
  # Output settings
  tag audio_recorder.recording  # Event tag (default: audio_recorder.recording)
  buffer_path /tmp/fluentd-audio-recorder # Temporary file path (default: /tmp/fluentd-audio-recorder)
  recording_interval 0    # Interval between recordings in seconds, 0 for continuous recording (default: 0)
</source>
```

## Output Record Format

```
{
  "path": "/path/to/recorded/audio/file.aac",    # Full path to the recorded file
  "filename": "20240302-123456_1709289368_0.aac", # Filename of the recorded file
  "size": 123456,                                # Size of the content in bytes
  "device": 0,                                   # Device number used for recording (from config)
  "format": "aac",                               # Audio codec used for recording (from config)
  "content": <binary data>                       # Binary content of the recorded file
}
```

## Requirements

- Ruby 3.4.1 or later
- fluentd v0.14.10 or later
- ffmpeg (installed on your system)
- macOS environment (uses avfoundation)

## Development and Testing

After checking out the repo, run `bundle install` to install dependencies.

To run the tests:

```bash
$ bundle exec rake test
```

## Troubleshooting

### Checking Available Devices

You can check available recording devices with the following command:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

### Checking Error Logs

Run fluentd in debug mode to see detailed logs:

```bash
fluentd -c fluent.conf -v
```
