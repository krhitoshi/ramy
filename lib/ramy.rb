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
  def to_br
    self.gsub(/\r\n/,'<br />').gsub(/(\r|\n)/,'<br />')
  end
end

class Ramy
  def initialize(prefix)
    @prefix = prefix
    @cgi = CGI.new
    if @cgi.query_string
      @cgi.params.merge(CGI::parse(@cgi.query_string)){|key, self_val, other_val| self_val }
    end

    @session = start_session(@cgi, @prefix, @prefix+".")

    @default_method = 'error'
    @methods = [:error]
    @method = param('mt')
    @action = param('ac')

    @title = ""
    @num_lines_in_page = 50 # 1ページに表示する行数
    @use_layout = true
  end
  def script_name
    File::basename($0)
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
      if @method.blank? 
        raise "メソッドが指定されていません｡"
      elsif @methods.include?(@method.intern)
        b = send(@method)
        output_bind(@method,b,@use_layout)
      else
        raise "不明なメソッドです｡ [#{@method}]"
      end
    rescue => error
      log(error.to_s + caller.to_s)
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
  def fatal_error(error)
    output_head
    print "Fatal Error: #{error}"
  end
  def output_head(head=nil)
    if head
      print @cgi.header(head)
    else
      print @cgi.header
    end
  end
  def output_bind(base,b,use_layout=true)
    title = @title
    main_html = get_rhtml(base).result(b)
     if use_layout
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
  def get_error
    str = pop_session('error')
    str.to_br if str
  end
  def get_message
    pop_session('message')
  end
  def set_message(str)
    @session['message'] = str
    session_update
  end
  def set_error(str)
    @session['error'] = str
    session_update
  end
  def error_exist?
    session_exist?('error')
  end
  def message_exist?
    session_exist?('message')
  end
  def session_exist?(key)
    if @session[key].to_s != ""
      true
    else
      false
    end
  end
  def start_session(cgi,key,prefix)
    CGI::Session.new(cgi, "session_key" => key,"prefix" => prefix,"session_expires" => Time.now + 60*60*24*365)
  end
  def delete_session_key(key)
      @session[key] = nil
  end
  def delete_session_keys(keys)
    keys.each{|key|
      delete_session_key(key)
    }
  end
  def session_delete
    @session.delete
  end
  def session_update
    @session.update
  end
  def get_values(keys)
    res = Array.new
    keys.each{|key|
      res << get_value(key.to_s)
    }
    res
  end
  def get_value(key)
    value = param(key)
    if value
      if value == ""
        @session[key] = nil
      else
        @session[key] = value
      end
    else
      value = @session[key]
    end
    value
  end
  def param_raw(keyword)
    @cgi.params[keyword][0]
  end
  def param(keyword)
    value = param_raw(keyword)
    # ファイルUPなどでPOSTがmultipartの場合
    if value.kind_of?(StringIO) || value.kind_of?(Tempfile)
      return value.read
    else
      return value
    end
  end
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
    (page - 1) * @num_lines_in_page
  end
  def calc_num_pages(num)
    num_pages, tmp = num.divmod(@num_lines_in_page)
    if tmp != 0
      num_pages += 1
    end
    num_pages
  end
  def Ramy.strip(value)
    unless value.blank?
      value.gsub(/(^(\s|　)+)|((\s|　)+$)/, '')
    else
      value
    end
  end
  def escape(value)
    CGI.escape(value)
  end
  def params_str
    @cgi.params.inspect + @session.inspect
  end
  def log(value)
    Syslog.open(@prefix)
    Syslog.log(Syslog::LOG_WARNING,value.to_s)
    Syslog.close
  end
end
