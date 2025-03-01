# fluent-plugin-audio-recorder

[Fluentd](https://fluentd.org/) input plugin to do something.

TODO: write description for you plugin.

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

You can generate configuration template:

```
$ fluent-plugin-config-format input audio-recorder
```

You can copy and paste generated documents here.

## Development and Testing

After checking out the repo, run `bundle install` to install dependencies.

To run the tests:

```bash
$ bundle exec rake test
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
  silence_duration 1.5    # 無音と判断する秒数（デフォルト: 1.0）
  noise_level -35         # 無音と判断するノイズレベル(dB)（デフォルト: -30）
  min_duration 3          # 最小録音時間(秒)（デフォルト: 2）
  max_duration 900        # 最大録音時間(秒)（デフォルト: 900 = 15分）
  
  # 音声設定
  audio_codec aac         # 音声コーデック（デフォルト: aac）
  audio_bitrate 192k      # 音声ビットレート（デフォルト: 192k）
  audio_sample_rate 44100 # 音声サンプルレート（デフォルト: 44100）
  audio_channels 1        # 音声チャンネル数（デフォルト: 1）
  
  # 出力設定
  tag audio.recording     # イベントタグ（デフォルト: audio.recording）
  buffer_path /tmp/fluentd-audio # 一時ファイル保存パス（デフォルト: /tmp/fluentd-audio-recorder）
</source>
```

## 出力レコード形式

```
{
  "path": "/path/to/recorded/audio/file.aac",
  "size": 123456,
  "timestamp": 1709289368,
  "device": 0,
  "duration": 45.2,
  "format": "aac"
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
