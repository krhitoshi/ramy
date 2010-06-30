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
  def strip
    if self.blank? 
      "" 
    else
      self.gsub(/(^(\s|　)+)|((\s|　)+$)/, '')
    end
  end
  def newline_to_br
    self.gsub(/\r\n/,'<br />').gsub(/(\r|\n)/,'<br />')
  end
end

class Ramy
  def initialize(prefix='ramy')
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
    @num_lines_in_page = 50
    @use_layout = true
  end
  def use_layout?
    @use_layout
  end
  def get_binding
    binding
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
    if @method.blank? 
      raise "メソッドが指定されていません｡"
    elsif @methods.include?(@method.intern)
      render_method(@method)
    else
      raise "不明なメソッドです｡ [#{@method}]"
    end
  rescue => error
    raise_error(error)
  end
  def error_method?
    @method.to_s == 'error'
  end
  def default_method?
    @method.to_s == @default_method.to_s
  end
  def raise_error(error)
    log(error.to_s + caller.to_s)
    set_error(error)
    if error_method?
      fatal_error(error)
    elsif default_method?
      redirect('error')
    else
      redirect(@default_method)      
    end
  end
  def render_method(method)
    send(method)
    print_html(method)
  end
  def redirect(method,option="")
    location = "#{script_name}?mt=#{method}"
    
    if option != ""
      location += "&#{option}"
    end
    print_header({ 'status' => '302 Found', 'Location' => location})
    exit
  end
  def fatal_error(error)
    print_header
    print "致命的なエラー: #{error}"
  end
  def print_header(headers="text/html")
    print @cgi.header(headers)
  end
  def print_html(method)
    main_html = get_html_base(method).result(binding)
    print_header
    print use_layout? ? get_layout{main_html} : main_html
  end
  def get_layout
    file = "views/layout/#{controller_name}.rhtml"
    get_html_file(file).result(binding)
  end
  def get_partial(method)
    get_html_base(method).result(binding)
  end
  def get_html_file(file)
    raise("テンプレートファイルが存在しません｡ [#{file}]") unless File.exist?(file)
    
    text = ""
    text += File.read(file)
    ERB.new(text,nil,"-")
  end
  def get_html_base(base)
    file = "views/#{controller_name}/#{base}.rhtml"
    get_html_file(file)
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
    str.newline_to_br if str
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
  def has_error?
    session_has_key?('error')
  end
  def has_message?
    session_has_key?('message')
  end
  def session_has_key?(key)
    @session[key].blank? ? true : false
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
      @session[key] = (value == "") ? nil : value
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
  def escape(value)
    CGI.escape(value)
  end
  def params_str
    @cgi.params.inspect + @session.inspect
  end
  def log(value)
    Syslog.open(@prefix){|syslog|
      syslog.log(Syslog::LOG_WARNING,value.to_s)
    }
  end
end
