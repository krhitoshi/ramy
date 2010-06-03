# -*- coding: utf-8 -*-

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'ramy'
require 'test/unit'
class TestRamy < Test::Unit::TestCase
  def setup
    ARGV.replace(["mt=error"])
    @ramy = Ramy.new('ramy_test')
#    @ramy.start
  end
  def test_strip
    values = [['2','2'],[' 2','2'],['2 ','2'],[' 2 ','2'],
              ['　2','2'],['2　','2'],['　2　','2'],
              ['さとみ','さとみ'],['　さとみ','さとみ'],['さとみ　','さとみ'],['　さとみ　','さとみ'],
              ['',''],[nil,nil],[' ',''],['　',''],[' 　 ',''],['　 　',''],
              ['高橋 義男','高橋 義男'],['高橋　義男','高橋　義男'],
              [' 高橋 義男 ','高橋 義男'],['　高橋　義男　','高橋　義男'],
              ['　高橋 義男　','高橋 義男'],[' 高橋　義男 ','高橋　義男']]
    values.each do |input,res|
      assert_equal(res,Ramy.strip(input),%Q!"#{input}" -> "#{res}"!)
    end
  end
  def test_object_blank
    values = [['',true],[nil,true],['2',false],[' ',false],['あ',false]]
    values.each do |input,res|
      assert_equal(res,input.blank?,%Q!"#{input}" -> "#{res}"!)
    end
  end
  def test_log
    assert_nothing_raised{ @ramy.log('log test') }
    assert_nothing_raised{ @ramy.log(12345) }
    assert_nothing_raised{ @ramy.log(nil) }
  end
end
