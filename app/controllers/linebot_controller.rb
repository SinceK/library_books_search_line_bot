class LinebotController < ApplicationController
  require 'line/bot'

  protect_from_forgery except: [:callback]

  @@libraries  = nil
  SEARCH_LIMIT = 5.freeze

  def client
    @client ||= Line::Bot::Client.new do |config|
      config.channel_secret = ENV['LINE_CHANNEL_SECRET']
      config.channel_token  = ENV['LINE_CHANNEL_TOKEN']
    end
  end

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head :bad_request
    end

    events = client.parse_events_from(body)

    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        # 位置情報
        when Line::Bot::Event::MessageType::Location
          # 図書館検索
          @@libraries = Calil::Library.find(
            geocode: "#{event.message['longitude']},#{event.message['latitude']}"
          ).index_by(&:systemid)

          reply_message(
            event['replyToken'],
            "位置情報の送信ありがとうございます。\n続けて『本のタイトル』を送信してください。"
          )

        # 書籍検索・蔵書検索
        when Line::Bot::Event::MessageType::Text
          title = event.message['text']

          if @@libraries.present? && title.present?

            begin
              # 楽天書籍API検索
              hit_books = RakutenWebService::Books::Book.search({
                title: title,
                hits: SEARCH_LIMIT
              }).index_by(&:isbn)
            rescue
              reply_message(
                event['replyToken'],
                "書籍検索中にエラーが発生しました。\nお手数ですが、もう一度『本のタイトル』を送信してください。"
              )
              return
            end

            begin
              text = []
              if hit_books.size == SEARCH_LIMIT
                text << "多数ヒットしたため、\n上位#{SEARCH_LIMIT}件を表示します。\n"
              else
                text << "#{hit_books.size}件ヒットしました。\n"
              end

              # 蔵書検索
              collection_books = Calil::Book.find(hit_books.keys, @@libraries.keys)

              collection_books.each do |collection_book|
                text << "■タイトル"
                text << hit_books[collection_book.isbn].title

                text << "■著者"
                text << hit_books[collection_book.isbn]&.author

                collection_book.systems.each do |system|
                  # 図書館名
                  text << "■#{@@libraries[system.systemid].formal}"
                  # 蔵書状況
                  text << (system.reservable? ? '蔵書あり' : '蔵書なし')
                  # 予約ページURL
                  text << system.reserveurl if system.reservable?
                end
                text << "\n"
              end

              reply_message(event['replyToken'], text.join("\n"))

            rescue Rack::Timeout::RequestTimeoutException
              reply_message(
                event['replyToken'],
                "蔵書検索中にエラーが発生しました。\nお手数ですが、もう一度『本のタイトル』を送信してください。"
              )
            end

          elsif @@libraries.blank?
            reply_message(
              event['replyToken'],
              "『位置情報』が送信されていません。\nまずは『位置情報』を送信してください。"
            )
          else
            reply_message(
              event['replyToken'],
              "『本のタイトル』が入力されていません。\nもう一度『本のタイトル』を送信してください。"
            )
          end

        else
          reply_message(
            event['replyToken'],
            "このBotは『位置情報』と『本のタイトル』で検索します。\nもう一度送信してください。"
          )
        end
      end
    end

    head :ok
  end

  private

  def reply_message(replyToken, text)
    client.reply_message(replyToken, { type: 'text', text: text })
  end
end
