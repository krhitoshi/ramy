# -*- coding: utf-8 -*-
#
#  ramy.rb
# 
#  Created by Hitoshi Kurokawa
#  Copyright 2010 Next SeeD. All rights reserved.

require 'cgi'
require 'cgi/session'
require 'erb'
require 'syslog'
require 'stringio'
require 'tempfile'
require 'kconv'

class Object
  def current_method
    caller.first.scan(/`(.*)'/).to_s
  end
  def blank?
    self.to_s.empty?
  end
end

class String
  # 改行コードをbrタグへ変換
  def to_br
    self.gsub(/\r\n/,'<br />').gsub(/(\r|\n)/,'<br />')
  end
end

class Ramy
  def initialize(prefix)
    @cgi = CGI.new
    @cgi.params.merge!(CGI::parse(@cgi.query_string)){|key, self_val, other_val| self_val }
    @session = start_session(@cgi, prefix, prefix+".")
    

    @default_method = 'error'
    @methods = [:error]
    @method = param('mt')
    @action = param('ac')

    @title = ""
    @page_list = 50 # 1ページに表示する行数
    @layout = true  # レイアウトの利用
  end
  def script_name
    @cgi.script_name
  end
  def controller_name
    File::basename(script_name,'.cgi')
  end
  def error
    @title = "エラー"
    binding
  end
  def start
    begin
      if @method.to_s != "" && @methods.include?(@method.intern)
        b = send(@method)
        output_bind(@method,b,@layout)
      else
        raise "不明なメソッドです｡ [#{@method}]"
      end
    rescue => error
      log(error)
      set_error(error)

      if @method.to_s == @default_method.to_s
        redirect('error')
      elsif @method.to_s != @default_method.to_s
        redirect(@default_method)
      else
        fatal_error(error)
      end
    end
  end
  def redirect(method,option="")
    location = "#{script_name}?mt=#{method}"
    if option != ""
      location += "&#{option}"
    end
    output_head({ 'status' => '302 Found', 'Location' => location})
  end
  # 致命的エラー発生時エラーを画面に出力
  def fatal_error(error)
    output_head
    print "Fatal Error: #{error}"
  end
  # ヘッダー出力
  def output_head(head=nil)
    if head
      print @cgi.header(head)
    else
      print @cgi.header
    end
  end
  # レイアウトが必要ない場合はlayout=falseにする
  def output_bind(base,b,layout=true)
    title = @title
    main_html = get_rhtml(base).result(b)
    if layout
      html = get_rhtml('application').result(binding)
    else
      html = main_html
    end
    output_head
    print html    
  end
  def get_partial(base)
    get_rhtml(base).result(binding)
  end
  def get_rhtml(base)
    file = "views/#{controller_name}/#{base}.rhtml"
    unless File.exist?(file)
      raise("File not found: [#{file}]")
    end

    text = ""
    text += File.read(file)
    ERB.new(text,nil,"-")
  end
  def set_default_method(method)
    @default_method = method
  end
  def set_methods(methods)
    @methods = methods
  end
  def pop_session(key)
    str = @session[key]
    @session[key] = nil
    session_update
    str
  end
  # エラーメッセージの取得
  def get_error
    str = pop_session('error')
    str.to_br
  end
  # メッセージの取得
  def get_message
    pop_session('message')
  end
  # メッセージ文字列のセット
  def set_message(str)
    @session['message'] = str
    session_update
  end
  # エラー文字列のセット
  def set_error(str)
    @session['error'] = str
    session_update
  end
  # エラーの存在確認
  def error_exist?
    session_exist?('error')
  end
  # メッセージの存在確認
  def message_exist?
    session_exist?('message')
  end
  # 指定したkeyのセッション値の存在確認
  def session_exist?(key)
    if @session[key].to_s != ""
      true
    else
      false
    end
  end
  # セッションのスタート
  def start_session(cgi,key,prefix)
    CGI::Session.new(cgi, "session_key" => key,"prefix" => prefix,"session_expires" => Time.now + 60*60*24*365)
  end
  # 指定した複数keyのセッション削除
  def delete_session_key(key)
      @session[key] = nil
  end
  def delete_session_keys(keys)
    keys.each{|key|
      delete_session_key(key)
    }
  end
  # セッションの削除
  def session_delete
    @session.delete
  end
  # セッションのアップデート(保存)
  def session_update
    @session.update
  end
  # 複数keyで値を取得
  def get_values(keys)
    res = Array.new
    keys.each{|key|
      res << get_value(key.to_s)
    }
    res
  end
  # パラメータもしくはセッションデータから値を取得
  def get_value(key)
    value = param(key)
    if value
      if value == ""
        @session[key] = nil
      else
        @session[key] = value # パラメータをセッションに保存
      end
    else
      value = @session[key]
    end
    value
  end
  # パラメータの生データ取得
  def param_raw(keyword)
    @cgi.params[keyword][0]
  end
  # パラメータの取得
  def param(keyword)
    value = param_raw(keyword)
    # ファイルUPなどでPOSTがmultipartの場合
    if value.kind_of?(StringIO) || value.kind_of?(Tempfile)
      return value.read
    else
      return value
    end
  end
  # 複数keyでパラメータを取得
  def params(keys)
    res = Array.new
    keys.each{|key|
      res << param(key.to_s)
    }
    res
  end
  def get_page(num_pages)
    page = nil
    value = get_value('page')
    if num_pages == 0 || value == 0 || value.blank?
      page = 1
    else
      if 1 <= value.to_i && value.to_i <= num_pages
        page = value.to_i
      else
        @session['page'] = nil
        session_update
        raise("存在しないページ指定です｡ ページ:#{value}")
      end
    end
    @session['page'] = page
    session_update
    page
  end
  def calc_limit(page)
    (page - 1) * @page_list
  end
  def calc_num_pages(num)
    num_pages, tmp = num.divmod(@page_list)
    if tmp != 0
      num_pages += 1
    end
    num_pages
  end
  # 文字列の前後の空白除去､空文字､nilの場合はそのまま返す
  def Ramy.strip(value)
    unless value.blank?
      value.gsub(/(^(\s|　)+)|((\s|　)+$)/, '')
    else
      value
    end
  end
  # 文字列をHTMLコードへエスケープ
  def escape(value)
    CGI.escape(value)
  end
  ########## デバッグ用 ##########
  # パラメータ内容を文字列で返す
  def params_str
    @cgi.params.inspect + @session.inspect
  end
  # Syslogへのログ出力
  def log(value)
    Syslog.open(@prefix)
    Syslog.log(Syslog::LOG_WARNING,value.to_s, 100)
    Syslog.close
  end
end
