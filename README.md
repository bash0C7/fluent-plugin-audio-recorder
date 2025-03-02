# fluent-plugin-audio-recorder

[Fluentd](https://fluentd.org/) input plugin for recording audio from macOS devices.

This plugin allows you to record audio from macOS devices with automatic silence detection for stopping recordings. It uses FFmpeg with avfoundation to capture audio and can be configured with various audio parameters.

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
  "path": "/path/to/recorded/audio/file.aac",
  "filename": "20240302-123456_1709289368_0.aac",
  "size": 123456,
  "device": 0,
  "format": "aac",
  "content": <binary data>
}
```

## Requirements

- Ruby 2.5.0 or later
- fluentd v1.0.0 or later
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

# fluent-plugin-audio-recorder

Fluentd用の録音入力プラグイン。macOS環境での録音デバイスからの音声収録と無音検出による自動停止機能を提供します。

## インストール

```
$ gem install fluent-plugin-audio-recorder
```

## 設定

```
<source>
  @type audio_recorder
  
  # 必須パラメータ
  device 0                # 録音するデバイス番号（整数）
  
  # オプションパラメータ
  silence_duration 1.0    # 無音と判断する秒数（デフォルト: 1.0）
  noise_level -30         # 無音と判断するノイズレベル(dB)（デフォルト: -30）
  min_duration 2          # 最小録音時間(秒)（デフォルト: 2）
  max_duration 900        # 最大録音時間(秒)（デフォルト: 900 = 15分）
  
  # 音声設定
  audio_codec aac         # 音声コーデック（デフォルト: aac）
  audio_bitrate 192k      # 音声ビットレート（デフォルト: 192k）
  audio_sample_rate 44100 # 音声サンプルレート（デフォルト: 44100）
  audio_channels 1        # 音声チャンネル数（デフォルト: 1）
  
  # 出力設定
  tag audio_recorder.recording  # イベントタグ（デフォルト: audio_recorder.recording）
  buffer_path /tmp/fluentd-audio-recorder # 一時ファイル保存パス（デフォルト: /tmp/fluentd-audio-recorder）
  recording_interval 0    # 録音間隔(秒)、0は連続録音（デフォルト: 0）
</source>
```

## 出力レコード形式

```
{
  "path": "/path/to/recorded/audio/file.aac",
  "filename": "20240302-123456_1709289368_0.aac",
  "size": 123456,
  "device": 0,
  "format": "aac",
  "content": <バイナリデータ>
}
```

## 必要条件

- Ruby 2.5.0以上
- fluentd v1.0.0以上
- ffmpeg（システムにインストールされていること）
- macOS環境（avfoundationを使用）

## 開発とテスト

リポジトリをクローンした後、`bundle install`で依存関係をインストールします。

テストを実行するには:

```bash
$ bundle exec rake test
```

## トラブルシューティング

### 利用可能なデバイスの確認方法

以下のコマンドで利用可能な録音デバイスを確認できます：

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

### エラーログの確認

デバッグモードで実行することで詳細なログを確認できます：

```bash
fluentd -c fluent.conf -v
```
