require 'spec_helper'
require 'capybara/webkit/driver'
require 'base64'

describe Capybara::Webkit::Driver do
  include AppRunner

  context "iframe app" do
    let(:driver) do
      driver_for_app do
        get "/" do
          if in_iframe_request?
            p_id = "farewell"
            msg  = "goodbye"
            iframe = nil
          else
            p_id = "greeting"
            msg  = "hello"
            iframe = "<iframe id=\"f\" src=\"/?iframe=true\"></iframe>"
          end
          <<-HTML
            <html>
              <head>
                <style type="text/css">
                  #display_none { display: none }
                </style>
              </head>
              <body>
                #{iframe}
                <script type="text/javascript">
                  document.write("<p id='#{p_id}'>#{msg}</p>");
                </script>
              </body>
            </html>
          HTML
        end

        def in_iframe_request?
          params[:iframe] == "true"
        end
      end
    end

    before do
      driver.visit("/")
    end

    it "finds frames by index" do
      driver.within_frame(0) do
        driver.find("//*[contains(., 'goodbye')]").should_not be_empty
      end
    end

    it "finds frames by id" do
      driver.within_frame("f") do
        driver.find("//*[contains(., 'goodbye')]").should_not be_empty
      end
    end

    it "raises error for missing frame by index" do
      expect { driver.within_frame(1) { } }.
        to raise_error(Capybara::Webkit::InvalidResponseError)
    end

    it "raise_error for missing frame by id" do
      expect { driver.within_frame("foo") { } }.
        to raise_error(Capybara::Webkit::InvalidResponseError)
    end

    it "returns an attribute's value" do
      driver.within_frame("f") do
        driver.find("//p").first["id"].should == "farewell"
      end
    end

    it "returns a node's text" do
      driver.within_frame("f") do
        driver.find("//p").first.text.should == "goodbye"
      end
    end

    it "returns the current URL" do
      driver.within_frame("f") do
        driver.current_url.should == driver_url(driver, "/?iframe=true")
      end
    end

    it "returns the source code for the page" do
      driver.within_frame("f") do
        driver.source.should =~ %r{<html>.*farewell.*}m
      end
    end

    it "evaluates Javascript" do
      driver.within_frame("f") do
        result = driver.evaluate_script(%<document.getElementById('farewell').innerText>)
        result.should == "goodbye"
      end
    end

    it "executes Javascript" do
      driver.within_frame("f") do
        driver.execute_script(%<document.getElementById('farewell').innerHTML = 'yo'>)
        driver.find("//p[contains(., 'yo')]").should_not be_empty
      end
    end
  end

  context "error iframe app" do
    let(:driver) do
      driver_for_app do
        get "/inner-not-found" do
          invalid_response
        end

        get "/" do
          <<-HTML
            <html>
              <body>
                <iframe src="/inner-not-found"></iframe>
              </body>
            </html>
          HTML
        end
      end
    end

    it "raises error whose message references the actual missing url" do
      expect { driver.visit("/") }.to raise_error(Capybara::Webkit::InvalidResponseError, /inner-not-found/)
    end
  end

  context "redirect app" do
    let(:driver) do
      driver_for_app do
        get '/target' do
          "<p>#{env['CONTENT_TYPE']}</p>"
        end

        get '/form' do
          <<-HTML
            <html>
              <body>
                <form action="/redirect" method="POST" enctype="multipart/form-data">
                  <input name="submit" type="submit" />
                </form>
              </body>
            </html>
          HTML
        end

        post '/redirect' do
          redirect '/target'
        end

        get '/redirect-me' do
          redirect '/target'
        end
      end
    end

    it "should redirect without content type" do
      driver.visit("/form")
      driver.find("//input").first.click
      driver.find("//p").first.text.should == ""
    end

    it "returns the current URL when changed by pushState after a redirect" do
      driver.visit("/redirect-me")
      driver.current_url.should == driver_url(driver, "/target")
      driver.execute_script("window.history.pushState({}, '', '/pushed-after-redirect')")
      driver.current_url.should == driver_url(driver, "/pushed-after-redirect")
    end

    it "returns the current URL when changed by replaceState after a redirect" do
      driver.visit("/redirect-me")
      driver.current_url.should == driver_url(driver, "/target")
      driver.execute_script("window.history.replaceState({}, '', '/replaced-after-redirect')")
      driver.current_url.should == driver_url(driver, "/replaced-after-redirect")
    end
  end

  context "css app" do
    let(:driver) do
      driver_for_app do
        get "/" do
          headers "Content-Type" => "text/css"
          "css"
        end
      end
    end

    before { driver.visit("/") }

    it "renders unsupported content types gracefully" do
      driver.body.should =~ /css/
    end

    it "sets the response headers with respect to the unsupported request" do
      driver.response_headers["Content-Type"].should == "text/css"
    end
  end

  context "hello app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html>
          <head>
            <style type="text/css">
              #display_none { display: none }
            </style>
          </head>
          <body>
            <div class='normalize'>Spaces&nbsp;not&nbsp;normalized&nbsp;</div>
            <div id="display_none">
              <div id="invisible">Can't see me</div>
            </div>
            <input type="text" disabled="disabled"/>
            <input id="checktest" type="checkbox" checked="checked"/>
            <script type="text/javascript">
              document.write("<p id='greeting'>he" + "llo</p>");
            </script>
          </body>
        </html>
      HTML
    end

    before { driver.visit("/") }

    it "handles anchor tags" do
      driver.visit("#test")
      driver.find("//*[contains(., 'hello')]").should_not be_empty
      driver.visit("#test")
      driver.find("//*[contains(., 'hello')]").should_not be_empty
    end

    it "finds content after loading a URL" do
      driver.find("//*[contains(., 'hello')]").should_not be_empty
    end

    it "has an empty page after reseting" do
      driver.reset!
      driver.find("//*[contains(., 'hello')]").should be_empty
    end

    it "has a blank location after reseting" do
      driver.reset!
      driver.current_url.should == ""
    end

    it "raises an error for an invalid xpath query" do
      expect { driver.find("totally invalid salad") }.
        to raise_error(Capybara::Webkit::InvalidResponseError, /xpath/i)
    end

    it "returns an attribute's value" do
      driver.find("//p").first["id"].should == "greeting"
    end

    it "parses xpath with quotes" do
      driver.find('//*[contains(., "hello")]').should_not be_empty
    end

    it "returns a node's text" do
      driver.find("//p").first.text.should == "hello"
    end

    it "normalizes a node's text" do
      driver.find("//div[contains(@class, 'normalize')]").first.text.should == "Spaces not normalized"
    end

    it "returns the current URL" do
      driver.visit "/hello/world?success=true"
      driver.current_url.should == driver_url(driver, "/hello/world?success=true")
    end

    it "returns the current URL when changed by pushState" do
      driver.execute_script("window.history.pushState({}, '', '/pushed')")
      driver.current_url.should == driver_url(driver, "/pushed")
    end

    it "returns the current URL when changed by replaceState" do
      driver.execute_script("window.history.replaceState({}, '', '/replaced')")
      driver.current_url.should == driver_url(driver, "/replaced")
    end

    it "does not double-encode URLs" do
      driver.visit("/hello/world?success=%25true")
      driver.current_url.should =~ /success=\%25true/
    end

    it "visits a page with an anchor" do
      driver.visit("/hello#display_none")
      driver.current_url.should =~ /hello#display_none/
    end

    it "returns the source code for the page" do
      driver.source.should =~ %r{<html>.*greeting.*}m
    end

    it "evaluates Javascript and returns a string" do
      result = driver.evaluate_script(%<document.getElementById('greeting').innerText>)
      result.should == "hello"
    end

    it "evaluates Javascript and returns an array" do
      result = driver.evaluate_script(%<["hello", "world"]>)
      result.should == %w(hello world)
    end

    it "evaluates Javascript and returns an int" do
      result = driver.evaluate_script(%<123>)
      result.should == 123
    end

    it "evaluates Javascript and returns a float" do
      result = driver.evaluate_script(%<1.5>)
      result.should == 1.5
    end

    it "evaluates Javascript and returns null" do
      result = driver.evaluate_script(%<(function () {})()>)
      result.should == nil
    end

    it "evaluates Javascript and returns an object" do
      result = driver.evaluate_script(%<({ 'one' : 1 })>)
      result.should == { 'one' => 1 }
    end

    it "evaluates Javascript and returns true" do
      result = driver.evaluate_script(%<true>)
      result.should === true
    end

    it "evaluates Javascript and returns false" do
      result = driver.evaluate_script(%<false>)
      result.should === false
    end

    it "evaluates Javascript and returns an escaped string" do
      result = driver.evaluate_script(%<'"'>)
      result.should === "\""
    end

    it "evaluates Javascript with multiple lines" do
      result = driver.evaluate_script("[1,\n2]")
      result.should == [1, 2]
    end

    it "executes Javascript" do
      driver.execute_script(%<document.getElementById('greeting').innerHTML = 'yo'>)
      driver.find("//p[contains(., 'yo')]").should_not be_empty
    end

    it "raises an error for failing Javascript" do
      expect { driver.execute_script(%<invalid salad>) }.
        to raise_error(Capybara::Webkit::InvalidResponseError)
    end

    it "doesn't raise an error for Javascript that doesn't return anything" do
      lambda { driver.execute_script(%<(function () { "returns nothing" })()>) }.
        should_not raise_error
    end

    it "returns a node's tag name" do
      driver.find("//p").first.tag_name.should == "p"
    end

    it "reads disabled property" do
      driver.find("//input").first.should be_disabled
    end

    it "reads checked property" do
      driver.find("//input[@id='checktest']").first.should be_checked
    end

    it "finds visible elements" do
      driver.find("//p").first.should be_visible
      driver.find("//*[@id='invisible']").first.should_not be_visible
    end
  end

  context "console messages app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html>
          <head>
          </head>
          <body>
            <script type="text/javascript">
              console.log("hello");
              console.log("hello again");
              oops
            </script>
          </body>
        </html>
      HTML
    end

    before { driver.visit("/") }

    it "collects messages logged to the console" do
      driver.console_messages.first.should include :source, :message => "hello", :line_number => 6
      driver.console_messages.length.should eq 3
    end

    it "logs errors to the console" do
      driver.error_messages.length.should eq 1
    end

    it "empties the array when reset" do
      driver.reset!
      driver.console_messages.should be_empty
    end

  end

  context "javascript dialog interaction" do
    context "on an alert app" do
      let(:driver) do
        driver_for_html(<<-HTML)
          <html>
            <head>
            </head>
            <body>
              <script type="text/javascript">
                alert("Alert Text Goes Here");
              </script>
            </body>
          </html>
        HTML
      end

      before { driver.visit("/") }

      it "should let me read my alert messages" do
        driver.alert_messages.first.should == "Alert Text Goes Here"
      end

      it "empties the array when reset" do
        driver.reset!
        driver.alert_messages.should be_empty
      end
    end

    context "on a confirm app" do
      let(:driver) do
        driver_for_html(<<-HTML)
          <html>
            <head>
            </head>
            <body>
              <script type="text/javascript">
                function test_dialog() {
                  if(confirm("Yes?"))
                    console.log("hello");
                  else
                    console.log("goodbye");
                }
              </script>
              <input type="button" onclick="test_dialog()" name="test"/>
            </body>
          </html>
        HTML
      end

      before { driver.visit("/") }

      it "should default to accept the confirm" do
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "hello"
      end

      it "can dismiss the confirm" do
        driver.dismiss_js_confirms!
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "goodbye"
      end

      it "can accept the confirm explicitly" do
        driver.dismiss_js_confirms!
        driver.accept_js_confirms!
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "hello"
      end

      it "should collect the javsacript confirm dialog contents" do
        driver.find("//input").first.click
        driver.confirm_messages.first.should == "Yes?"
      end

      it "empties the array when reset" do
        driver.find("//input").first.click
        driver.reset!
        driver.confirm_messages.should be_empty
      end

      it "resets to the default of accepting confirms" do
        driver.dismiss_js_confirms!
        driver.reset!
        driver.visit("/")
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "hello"
      end
    end

    context "on a prompt app" do
      let(:driver) do
        driver_for_html(<<-HTML)
          <html>
            <head>
            </head>
            <body>
              <script type="text/javascript">
                function test_dialog() {
                  var response = prompt("Your name?", "John Smith");
                  if(response != null)
                    console.log("hello " + response);
                  else
                    console.log("goodbye");
                }
              </script>
              <input type="button" onclick="test_dialog()" name="test"/>
            </body>
          </html>
        HTML
      end

      before { driver.visit("/") }

      it "should default to dismiss the prompt" do
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "goodbye"
      end

      it "can accept the prompt without providing text" do
        driver.accept_js_prompts!
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "hello John Smith"
      end

      it "can accept the prompt with input" do
        driver.js_prompt_input = "Capy"
        driver.accept_js_prompts!
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "hello Capy"
      end

      it "can return to dismiss the prompt after accepting prompts" do
        driver.accept_js_prompts!
        driver.dismiss_js_prompts!
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "goodbye"
      end

      it "should let me remove the prompt input text" do
        driver.js_prompt_input = "Capy"
        driver.accept_js_prompts!
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "hello Capy"
        driver.js_prompt_input = nil
        driver.find("//input").first.click
        driver.console_messages.last[:message].should == "hello John Smith"
      end

      it "should collect the javsacript prompt dialog contents" do
        driver.find("//input").first.click
        driver.prompt_messages.first.should == "Your name?"
      end

      it "empties the array when reset" do
        driver.find("//input").first.click
        driver.reset!
        driver.prompt_messages.should be_empty
      end

      it "returns the prompt action to dismiss on reset" do
        driver.accept_js_prompts!
        driver.reset!
        driver.visit("/")
        driver.find("//input").first.click
        driver.console_messages.first[:message].should == "goodbye"
      end
    end
  end

  context "form app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html><body>
          <form action="/" method="GET">
            <input type="text" name="foo" value="bar"/>
            <input type="text" name="maxlength_foo" value="bar" maxlength="10"/>
            <input type="text" id="disabled_input" disabled="disabled"/>
            <input type="checkbox" name="checkedbox" value="1" checked="checked"/>
            <input type="checkbox" name="uncheckedbox" value="2"/>
            <select name="animal">
              <option id="select-option-monkey">Monkey</option>
              <option id="select-option-capybara" selected="selected">Capybara</option>
            </select>
            <select name="toppings" multiple="multiple">
              <optgroup label="Mediocre Toppings">
                <option selected="selected" id="topping-apple">Apple</option>
                <option selected="selected" id="topping-banana">Banana</option>
              </optgroup>
              <optgroup label="Best Toppings">
                <option selected="selected" id="topping-cherry">Cherry</option>
              </optgroup>
            </select>
            <select name="guitars" multiple>
              <option selected="selected" id="fender">Fender</option>
              <option selected="selected" id="gibson">Gibson</option>
            </select>
            <textarea id="only-textarea">what a wonderful area for text</textarea>
            <input type="radio" id="only-radio" value="1"/>
            <button type="reset">Reset Form</button>
          </form>
        </body></html>
      HTML
    end

    before { driver.visit("/") }

    it "returns a textarea's value" do
      driver.find("//textarea").first.value.should == "what a wonderful area for text"
    end

    it "returns a text input's value" do
      driver.find("//input").first.value.should == "bar"
    end

    it "returns a select's value" do
      driver.find("//select").first.value.should == "Capybara"
    end

    it "sets an input's value" do
      input = driver.find("//input").first
      input.set("newvalue")
      input.value.should == "newvalue"
    end

    it "sets an input's value greater than the max length" do
      input = driver.find("//input[@name='maxlength_foo']").first
      input.set("allegories (poems)")
      input.value.should == "allegories"
    end

    it "sets an input's value equal to the max length" do
      input = driver.find("//input[@name='maxlength_foo']").first
      input.set("allegories")
      input.value.should == "allegories"
    end

    it "sets an input's value less than the max length" do
      input = driver.find("//input[@name='maxlength_foo']").first
      input.set("poems")
      input.value.should == "poems"
    end

    it "sets an input's nil value" do
      input = driver.find("//input").first
      input.set(nil)
      input.value.should == ""
    end

    it "sets a select's value" do
      select = driver.find("//select").first
      select.set("Monkey")
      select.value.should == "Monkey"
    end

    it "sets a textarea's value" do
      textarea = driver.find("//textarea").first
      textarea.set("newvalue")
      textarea.value.should == "newvalue"
    end

    let(:monkey_option)   { driver.find("//option[@id='select-option-monkey']").first }
    let(:capybara_option) { driver.find("//option[@id='select-option-capybara']").first }
    let(:animal_select)   { driver.find("//select[@name='animal']").first }
    let(:apple_option)    { driver.find("//option[@id='topping-apple']").first }
    let(:banana_option)   { driver.find("//option[@id='topping-banana']").first }
    let(:cherry_option)   { driver.find("//option[@id='topping-cherry']").first }
    let(:toppings_select) { driver.find("//select[@name='toppings']").first }
    let(:guitars_select)  { driver.find("//select[@name='guitars']").first }
    let(:fender_option)   { driver.find("//option[@id='fender']").first }
    let(:reset_button)    { driver.find("//button[@type='reset']").first }

    context "a select element's selection has been changed" do
      before do
        animal_select.value.should == "Capybara"
        monkey_option.select_option
      end

      it "returns the new selection" do
        animal_select.value.should == "Monkey"
      end

      it "does not modify the selected attribute of a new selection" do
        monkey_option['selected'].should be_empty
      end

      it "returns the old value when a reset button is clicked" do
        reset_button.click

        animal_select.value.should == "Capybara"
      end
    end

    context "a multi-select element's option has been unselected" do
      before do
        toppings_select.value.should include("Apple", "Banana", "Cherry")

        apple_option.unselect_option
      end

      it "does not return the deselected option" do
        toppings_select.value.should_not include("Apple")
      end

      it "returns the deselected option when a reset button is clicked" do
        reset_button.click

        toppings_select.value.should include("Apple", "Banana", "Cherry")
      end
    end

    context "a multi-select (with empty multiple attribute) element's option has been unselected" do
      before do
        guitars_select.value.should include("Fender", "Gibson")

        fender_option.unselect_option
      end

      it "does not return the deselected option" do
        guitars_select.value.should_not include("Fender")
      end
    end

    it "reselects an option in a multi-select" do
      apple_option.unselect_option
      banana_option.unselect_option
      cherry_option.unselect_option

      toppings_select.value.should == []

      apple_option.select_option
      banana_option.select_option
      cherry_option.select_option

      toppings_select.value.should include("Apple", "Banana", "Cherry")
    end

    let(:checked_box) { driver.find("//input[@name='checkedbox']").first }
    let(:unchecked_box) { driver.find("//input[@name='uncheckedbox']").first }

    it "knows a checked box is checked" do
      checked_box['checked'].should be_true
    end

    it "knows a checked box is checked using checked?" do
      checked_box.should be_checked
    end

    it "knows an unchecked box is unchecked" do
      unchecked_box['checked'].should_not be_true
    end

    it "knows an unchecked box is unchecked using checked?" do
      unchecked_box.should_not be_checked
    end

    it "checks an unchecked box" do
      unchecked_box.set(true)
      unchecked_box.should be_checked
    end

    it "unchecks a checked box" do
      checked_box.set(false)
      checked_box.should_not be_checked
    end

    it "leaves a checked box checked" do
      checked_box.set(true)
      checked_box.should be_checked
    end

    it "leaves an unchecked box unchecked" do
      unchecked_box.set(false)
      unchecked_box.should_not be_checked
    end

    let(:enabled_input)  { driver.find("//input[@name='foo']").first }
    let(:disabled_input) { driver.find("//input[@id='disabled_input']").first }

    it "knows a disabled input is disabled" do
      disabled_input['disabled'].should be_true
    end

    it "knows a not disabled input is not disabled" do
      enabled_input['disabled'].should_not be_true
    end
  end

  context "dom events" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html><body>
          <a href='#' class='watch'>Link</a>
          <ul id="events"></ul>
          <script type="text/javascript">
            var events = document.getElementById("events");
            var recordEvent = function (event) {
              var element = document.createElement("li");
              element.innerHTML = event.type;
              events.appendChild(element);
            };

            var elements = document.getElementsByClassName("watch");
            for (var i = 0; i < elements.length; i++) {
              var element = elements[i];
              element.addEventListener("mousedown", recordEvent);
              element.addEventListener("mouseup", recordEvent);
              element.addEventListener("click", recordEvent);
            }
          </script>
        </body></html>
      HTML
    end

    before { driver.visit("/") }

    it "triggers mouse events" do
      driver.find("//a").first.click
      driver.find("//li").map(&:text).should == %w(mousedown mouseup click)
    end
  end

  context "form events app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html><body>
          <form action="/" method="GET">
            <input class="watch" type="email"/>
            <input class="watch" type="number"/>
            <input class="watch" type="password"/>
            <input class="watch" type="search"/>
            <input class="watch" type="tel"/>
            <input class="watch" type="text"/>
            <input class="watch" type="url"/>
            <textarea class="watch"></textarea>
            <input class="watch" type="checkbox"/>
            <input class="watch" type="radio"/>
          </form>
          <ul id="events"></ul>
          <script type="text/javascript">
            var events = document.getElementById("events");
            var recordEvent = function (event) {
              var element = document.createElement("li");
              element.innerHTML = event.type;
              events.appendChild(element);
            };

            var elements = document.getElementsByClassName("watch");
            for (var i = 0; i < elements.length; i++) {
              var element = elements[i];
              element.addEventListener("focus", recordEvent);
              element.addEventListener("keydown", recordEvent);
              element.addEventListener("keypress", recordEvent);
              element.addEventListener("keyup", recordEvent);
              element.addEventListener("input", recordEvent);
              element.addEventListener("change", recordEvent);
              element.addEventListener("blur", recordEvent);
              element.addEventListener("mousedown", recordEvent);
              element.addEventListener("mouseup", recordEvent);
              element.addEventListener("click", recordEvent);
            }
          </script>
        </body></html>
      HTML
    end

    before { driver.visit("/") }

    let(:newtext) { 'newvalue' }

    let(:keyevents) do
      (%w{focus} +
       newtext.length.times.collect { %w{keydown keypress keyup input} } +
       %w{change}).flatten
    end

    %w(email number password search tel text url).each do | field_type |
      it "triggers text input events on inputs of type #{field_type}" do
        driver.find("//input[@type='#{field_type}']").first.set(newtext)
        driver.find("//li").map(&:text).should == keyevents
      end
    end

    it "triggers textarea input events" do
      driver.find("//textarea").first.set(newtext)
      driver.find("//li").map(&:text).should == keyevents
    end

    it "triggers radio input events" do
      driver.find("//input[@type='radio']").first.set(true)
      driver.find("//li").map(&:text).should == %w(mousedown focus mouseup change click)
    end

    it "triggers checkbox events" do
      driver.find("//input[@type='checkbox']").first.set(true)
      driver.find("//li").map(&:text).should == %w(mousedown focus mouseup change click)
    end
  end

  context "mouse app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html><body>
          <div id="change">Change me</div>
          <div id="mouseup">Push me</div>
          <div id="mousedown">Release me</div>
          <form action="/" method="GET">
            <select id="change_select" name="change_select">
              <option value="1" id="option-1" selected="selected">one</option>
              <option value="2" id="option-2">two</option>
            </select>
          </form>
          <script type="text/javascript">
            document.getElementById("change_select").
              addEventListener("change", function () {
                this.className = "triggered";
              });
            document.getElementById("change").
              addEventListener("change", function () {
                this.className = "triggered";
              });
            document.getElementById("mouseup").
              addEventListener("mouseup", function () {
                this.className = "triggered";
              });
            document.getElementById("mousedown").
              addEventListener("mousedown", function () {
                this.className = "triggered";
              });
          </script>
          <a href="/next">Next</a>
        </body></html>
      HTML
    end

    before { driver.visit("/") }

    it "clicks an element" do
      driver.find("//a").first.click
      driver.current_url =~ %r{/next$}
    end

    it "fires a mouse event" do
      driver.find("//*[@id='mouseup']").first.trigger("mouseup")
      driver.find("//*[@class='triggered']").should_not be_empty
    end

    it "fires a non-mouse event" do
      driver.find("//*[@id='change']").first.trigger("change")
      driver.find("//*[@class='triggered']").should_not be_empty
    end

    it "fires a change on select" do
      select = driver.find("//select").first
      select.value.should == "1"
      option = driver.find("//option[@id='option-2']").first
      option.select_option
      select.value.should == "2"
      driver.find("//select[@class='triggered']").should_not be_empty
    end

    it "fires drag events" do
      draggable = driver.find("//*[@id='mousedown']").first
      container = driver.find("//*[@id='mouseup']").first

      draggable.drag_to(container)

      driver.find("//*[@class='triggered']").size.should == 1
    end
  end

  context "nesting app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html><body>
          <div id="parent">
            <div class="find">Expected</div>
          </div>
          <div class="find">Unexpected</div>
        </body></html>
      HTML
    end

    before { driver.visit("/") }

    it "evaluates nested xpath expressions" do
      parent = driver.find("//*[@id='parent']").first
      parent.find("./*[@class='find']").map(&:text).should == %w(Expected)
    end
  end

  context "slow app" do
    it "waits for a request to load" do
      result = ""
      driver = driver_for_app do
        get "/result" do
          sleep(0.5)
          result << "finished"
          ""
        end

        get "/" do
          %{<html><body><a href="/result">Go</a></body></html>}
        end
      end
      driver.visit("/")
      driver.find("//a").first.click
      result.should == "finished"
    end
  end

  context "error app" do
    let(:driver) do
      driver_for_app do
        get "/error" do
          invalid_response
        end

        get "/" do
          <<-HTML
            <html><body>
              <form action="/error"><input type="submit"/></form>
            </body></html>
          HTML
        end
      end
    end

    before { driver.visit("/") }

    it "raises a webkit error for the requested url" do
      expect {
        driver.find("//input").first.click
        wait_for_error_to_complete
        driver.find("//body")
      }.
        to raise_error(Capybara::Webkit::InvalidResponseError, %r{/error})
    end

    def wait_for_error_to_complete
      sleep(0.5)
    end
  end

  context "slow error app" do
    let(:driver) do
      driver_for_app do
        get "/error" do
          sleep(1)
          invalid_response
        end

        get "/" do
          <<-HTML
            <html><body>
              <form action="/error"><input type="submit"/></form>
              <p>hello</p>
            </body></html>
          HTML
        end
      end
    end

    before { driver.visit("/") }

    it "raises a webkit error and then continues" do
      driver.find("//input").first.click
      expect { driver.find("//p") }.to raise_error(Capybara::Webkit::InvalidResponseError)
      driver.visit("/")
      driver.find("//p").first.text.should == "hello"
    end
  end

  context "popup app" do
    let(:driver) do
      driver_for_app do
        get "/" do
          sleep(0.5)
          return <<-HTML
            <html><body>
              <script type="text/javascript">
                alert("alert");
                confirm("confirm");
                prompt("prompt");
              </script>
              <p>success</p>
            </body></html>
          HTML
        end
      end
    end

    before { driver.visit("/") }

    it "doesn't crash from alerts" do
      driver.find("//p").first.text.should == "success"
    end
  end

  context "custom header" do
    let(:driver) do
      driver_for_app do
        get "/" do
          <<-HTML
            <html><body>
              <p id="user-agent">#{env['HTTP_USER_AGENT']}</p>
              <p id="x-capybara-webkit-header">#{env['HTTP_X_CAPYBARA_WEBKIT_HEADER']}</p>
              <p id="accept">#{env['HTTP_ACCEPT']}</p>
              <a href="/">/</a>
            </body></html>
          HTML
        end
      end
    end

    before { driver.visit("/") }

    before do
      driver.header('user-agent', 'capybara-webkit/custom-user-agent')
      driver.header('x-capybara-webkit-header', 'x-capybara-webkit-header')
      driver.header('accept', 'text/html')
      driver.visit('/')
    end

    it "can set user_agent" do
      driver.find('id("user-agent")').first.text.should == 'capybara-webkit/custom-user-agent'
      driver.evaluate_script('navigator.userAgent').should == 'capybara-webkit/custom-user-agent'
    end

    it "keep user_agent in next page" do
      driver.find("//a").first.click
      driver.find('id("user-agent")').first.text.should == 'capybara-webkit/custom-user-agent'
      driver.evaluate_script('navigator.userAgent').should == 'capybara-webkit/custom-user-agent'
    end

    it "can set custom header" do
      driver.find('id("x-capybara-webkit-header")').first.text.should == 'x-capybara-webkit-header'
    end

    it "can set Accept header" do
      driver.find('id("accept")').first.text.should == 'text/html'
    end

    it "can reset all custom header" do
      driver.reset!
      driver.visit('/')
      driver.find('id("user-agent")').first.text.should_not == 'capybara-webkit/custom-user-agent'
      driver.evaluate_script('navigator.userAgent').should_not == 'capybara-webkit/custom-user-agent'
      driver.find('id("x-capybara-webkit-header")').first.text.should be_empty
      driver.find('id("accept")').first.text.should_not == 'text/html'
    end
  end

  context "no response app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html><body>
          <form action="/error"><input type="submit"/></form>
        </body></html>
      HTML
    end

    before { driver.visit("/") }

    it "raises a webkit error for the requested url" do
      make_the_server_go_away
      expect {
        driver.find("//body")
      }.
       to raise_error(Capybara::Webkit::NoResponseError, %r{response})
      make_the_server_come_back
    end

    def make_the_server_come_back
      driver.browser.instance_variable_get(:@connection).unstub!(:gets)
      driver.browser.instance_variable_get(:@connection).unstub!(:puts)
      driver.browser.instance_variable_get(:@connection).unstub!(:print)
    end

    def make_the_server_go_away
      driver.browser.instance_variable_get(:@connection).stub!(:gets).and_return(nil)
      driver.browser.instance_variable_get(:@connection).stub!(:puts)
      driver.browser.instance_variable_get(:@connection).stub!(:print)
    end
  end

  context "custom font app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html>
          <head>
            <style type="text/css">
              p { font-family: "Verdana"; }
            </style>
          </head>
          <body>
            <p id="text">Hello</p>
          </body>
        </html>
      HTML
    end

    before { driver.visit("/") }

    it "ignores custom fonts" do
      font_family = driver.evaluate_script(<<-SCRIPT)
        var element = document.getElementById("text");
        element.ownerDocument.defaultView.getComputedStyle(element, null).getPropertyValue("font-family");
      SCRIPT
      font_family.should == "Arial"
    end
  end

  context "cookie-based app" do
    let(:driver) do
      driver_for_app do
        get "/" do
          headers 'Set-Cookie' => 'cookie=abc; domain=127.0.0.1; path=/'
          <<-HTML
            <html><body>
              <p id="cookie">#{request.cookies["cookie"] || ""}</p>
            </body></html>
          HTML
        end
      end
    end

    before { driver.visit("/") }

    def echoed_cookie
      driver.find('id("cookie")').first.text
    end

    it "remembers the cookie on second visit" do
      echoed_cookie.should == ""
      driver.visit "/"
      echoed_cookie.should == "abc"
    end

    it "uses a custom cookie" do
      driver.browser.set_cookie 'cookie=abc; domain=127.0.0.1; path=/'
      driver.visit "/"
      echoed_cookie.should == "abc"
    end

    it "clears cookies" do
      driver.browser.clear_cookies
      driver.visit "/"
      echoed_cookie.should == ""
    end

    it "allows enumeration of cookies" do
      cookies = driver.browser.get_cookies

      cookies.size.should == 1

      cookie = Hash[cookies[0].split(/\s*;\s*/).map { |x| x.split("=", 2) }]
      cookie["cookie"].should == "abc"
      cookie["domain"].should include "127.0.0.1"
      cookie["path"].should == "/"
    end

    it "allows reading access to cookies using a nice syntax" do
      driver.cookies["cookie"].should == "abc"
    end
  end

  context "remove node app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html>
          <div id="parent">
            <p id="removeMe">Hello</p>
          </div>
        </html>
      HTML
    end

    before { driver.visit("/") }

    before { set_automatic_reload false }
    after { set_automatic_reload true }

    def set_automatic_reload(value)
      if Capybara.respond_to?(:automatic_reload)
        Capybara.automatic_reload = value
      end
    end

    it "allows removed nodes when reloading is disabled" do
      node = driver.find("//p[@id='removeMe']").first
      driver.evaluate_script("document.getElementById('parent').innerHTML = 'Magic'")
      node.text.should == 'Hello'
    end
  end

  context "app with a lot of HTML tags" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html>
          <head>
            <title>My eBook</title>
            <meta class="charset" name="charset" value="utf-8" />
            <meta class="author" name="author" value="Firstname Lastname" />
          </head>
          <body>
            <div id="toc">
              <table>
                <thead id="head">
                  <tr><td class="td1">Chapter</td><td>Page</td></tr>
                </thead>
                <tbody>
                  <tr><td>Intro</td><td>1</td></tr>
                  <tr><td>Chapter 1</td><td class="td2">1</td></tr>
                  <tr><td>Chapter 2</td><td>1</td></tr>
                </tbody>
              </table>
            </div>

            <h1 class="h1">My first book</h1>
            <p class="p1">Written by me</p>
            <div id="intro" class="intro">
              <p>Let's try out XPath</p>
              <p class="p2">in capybara-webkit</p>
            </div>

            <h2 class="chapter1">Chapter 1</h2>
            <p>This paragraph is fascinating.</p>
            <p class="p3">But not as much as this one.</p>

            <h2 class="chapter2">Chapter 2</h2>
            <p>Let's try if we can select this</p>
          </body>
        </html>
      HTML
    end

    before { driver.visit("/") }

    it "builds up node paths correctly" do
      cases = {
        "//*[contains(@class, 'author')]"    => "/html/head/meta[2]",
        "//*[contains(@class, 'td1')]"       => "/html/body/div[@id='toc']/table/thead[@id='head']/tr/td[1]",
        "//*[contains(@class, 'td2')]"       => "/html/body/div[@id='toc']/table/tbody/tr[2]/td[2]",
        "//h1"                               => "/html/body/h1",
        "//*[contains(@class, 'chapter2')]"  => "/html/body/h2[2]",
        "//*[contains(@class, 'p1')]"        => "/html/body/p[1]",
        "//*[contains(@class, 'p2')]"        => "/html/body/div[@id='intro']/p[2]",
        "//*[contains(@class, 'p3')]"        => "/html/body/p[3]",
      }

      cases.each do |xpath, path|
        nodes = driver.find(xpath)
        nodes.size.should == 1
        nodes[0].path.should == path
      end
    end
  end

  context "css overflow app" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html>
          <head>
            <style type="text/css">
              #overflow { overflow: hidden }
            </style>
          </head>
          <body>
            <div id="overflow">Overflow</div>
          </body>
        </html>
      HTML
    end

    before { driver.visit("/") }

    it "handles overflow hidden" do
      driver.find("//div[@id='overflow']").first.text.should == "Overflow"
    end
  end

  context "javascript redirect app" do
    let(:driver) do
      driver_for_app do
        get '/redirect' do
          <<-HTML
            <html>
              <script type="text/javascript">
                window.location = "/";
              </script>
            </html>
          HTML
        end

        get '/' do
          "<html><p>finished</p></html>"
        end
      end
    end

    it "loads a page without error" do
      10.times do
        driver.visit("/redirect")
        driver.find("//p").first.text.should == "finished"
      end
    end
  end

  context "localStorage works" do
    let(:driver) do
      driver_for_html(<<-HTML)
        <html>
          <body>
            <span id='output'></span>
            <script type="text/javascript">
              if (typeof localStorage !== "undefined") {
                if (!localStorage.refreshCounter) {
                  localStorage.refreshCounter = 0;
                }
                if (localStorage.refreshCounter++ > 0) {
                  document.getElementById("output").innerHTML = "localStorage is enabled";
                }
              }
            </script>
          </body>
        </html>
      HTML
    end

    before { driver.visit("/") }

    it "displays the message on subsequent page loads" do
      driver.find("//span[contains(.,'localStorage is enabled')]").should be_empty
      driver.visit "/"
      driver.find("//span[contains(.,'localStorage is enabled')]").should_not be_empty
    end
  end

  context "form app with server-side handler" do
    let(:driver) do
      driver_for_app do
        post "/" do
          "<html><body><p>Congrats!</p></body></html>"
        end

        get "/" do
          <<-HTML
            <html>
              <head><title>Form</title>
              <body>
                <form action="/" method="POST">
                  <input type="hidden" name="abc" value="123" />
                  <input type="submit" value="Submit" />
                </form>
              </body>
            </html>
          HTML
        end
      end
    end

    before { driver.visit("/") }

    it "submits a form without clicking" do
      driver.find("//form")[0].submit
      driver.body.should include "Congrats"
    end
  end

  def driver_for_key_body(event)
    driver_for_app do
      get "/" do
        <<-HTML
          <html>
            <head><title>Form</title></head>
            <body>
              <div id="charcode_value"></div>
              <div id="keycode_value"></div>
              <div id="which_value"></div>
              <input type="text" id="charcode" name="charcode" on#{event}="setcharcode" />
              <script type="text/javascript">
                var element = document.getElementById("charcode")
                element.addEventListener("#{event}", setcharcode);
                function setcharcode(event) {
                  var element = document.getElementById("charcode_value");
                  element.innerHTML = event.charCode;
                  element = document.getElementById("keycode_value");
                  element.innerHTML = event.keyCode;
                  element = document.getElementById("which_value");
                  element.innerHTML = event.which;
                }
              </script>
            </body>
          </html>
        HTML
      end
    end
  end

  def charCode_for(character)
    driver.find("//input")[0].set(character)
    driver.find("//div[@id='charcode_value']")[0].text
  end

  def keyCode_for(character)
    driver.find("//input")[0].set(character)
    driver.find("//div[@id='keycode_value']")[0].text
  end

  def which_for(character)
    driver.find("//input")[0].set(character)
    driver.find("//div[@id='which_value']")[0].text
  end

  context "keypress app" do
    let(:driver) { driver_for_key_body "keypress" }

    before { driver.visit("/") }

    it "returns the charCode for the keypressed" do
      charCode_for("a").should == "97"
      charCode_for("A").should == "65"
      charCode_for("\r").should == "13"
      charCode_for(",").should == "44"
      charCode_for("<").should == "60"
      charCode_for("0").should == "48"
    end

    it "returns the keyCode for the keypressed" do
      keyCode_for("a").should == "97"
      keyCode_for("A").should == "65"
      keyCode_for("\r").should == "13"
      keyCode_for(",").should == "44"
      keyCode_for("<").should == "60"
      keyCode_for("0").should == "48"
    end

    it "returns the which for the keypressed" do
      which_for("a").should == "97"
      which_for("A").should == "65"
      which_for("\r").should == "13"
      which_for(",").should == "44"
      which_for("<").should == "60"
      which_for("0").should == "48"
    end
  end

  shared_examples "a keyupdown app" do
    it "returns a 0 charCode for the event" do
      charCode_for("a").should == "0"
      charCode_for("A").should == "0"
      charCode_for("\r").should == "0"
      charCode_for(",").should == "0"
      charCode_for("<").should == "0"
      charCode_for("0").should == "0"
    end

    it "returns the keyCode for the event" do
      keyCode_for("a").should == "65"
      keyCode_for("A").should == "65"
      keyCode_for("\r").should == "13"
      keyCode_for(",").should == "188"
      keyCode_for("<").should == "188"
      keyCode_for("0").should == "48"
    end

    it "returns the which for the event" do
      which_for("a").should == "65"
      which_for("A").should == "65"
      which_for("\r").should == "13"
      which_for(",").should == "188"
      which_for("<").should == "188"
      which_for("0").should == "48"
    end
  end

  context "keydown app" do
    let(:driver) { driver_for_key_body "keydown" }
    before { driver.visit("/") }
    it_behaves_like "a keyupdown app"
  end

  context "keyup app" do
    let(:driver) { driver_for_key_body "keyup" }
    before { driver.visit("/") }
    it_behaves_like "a keyupdown app"
  end

  context "null byte app" do
    let(:driver) do
      driver_for_html("Hello\0World")
    end

    before { driver.visit("/") }

    it "should include all the bytes in the source" do
      driver.source.should == "Hello\0World"
    end
  end

  context "javascript new window app" do
    let(:driver) do
      driver_for_app do
        get '/new_window' do
          <<-HTML
            <html>
              <script type="text/javascript">
                window.open('http://#{request.host_with_port}/?#{request.query_string}', 'myWindow');
              </script>
              <p>bananas</p>
            </html>
          HTML
        end

        get "/" do
          sleep params['sleep'].to_i if params['sleep']
          "<html><head><title>My New Window</title></head><body><p>finished</p></body></html>"
        end
      end
    end

    before { driver.visit("/") }

    it "has the expected text in the new window" do
      driver.visit("/new_window")
      driver.within_window(driver.window_handles.last) do
        driver.find("//p").first.text.should == "finished"
      end
    end

    it "waits for the new window to load" do
      driver.visit("/new_window?sleep=1")
      driver.within_window(driver.window_handles.last) do
        driver.find("//p").first.text.should == "finished"
      end
    end

    it "waits for the new window to load when the window location has changed" do
      driver.visit("/new_window?sleep=2")
      driver.execute_script("setTimeout(function() { window.location = 'about:blank' }, 1000)")
      driver.within_window(driver.window_handles.last) do
        driver.find("//p").first.text.should == "finished"
      end
    end

    it "switches back to the original window" do
      driver.visit("/new_window")
      driver.within_window(driver.window_handles.last) { }
      driver.find("//p").first.text.should == "bananas"
    end

    it "supports finding a window by name" do
      driver.visit("/new_window")
      driver.within_window('myWindow') do
        driver.find("//p").first.text.should == "finished"
      end
    end

    it "supports finding a window by title" do
      driver.visit("/new_window?sleep=5")
      driver.within_window('My New Window') do
        driver.find("//p").first.text.should == "finished"
      end
    end

    it "supports finding a window by url" do
      driver.visit("/new_window?test")
      driver.within_window(driver_url(driver, "/?test")) do
        driver.find("//p").first.text.should == "finished"
      end
    end

    it "raises an error if the window is not found" do
      expect { driver.within_window('myWindowDoesNotExist') }.
        to raise_error(Capybara::Webkit::InvalidResponseError)
    end

    it "has a number of window handles equal to the number of open windows" do
      driver.window_handles.size.should == 1
      driver.visit("/new_window")
      driver.window_handles.size.should == 2
    end

    it "closes new windows on reset" do
      driver.visit("/new_window")
      last_handle = driver.window_handles.last
      driver.reset!
      driver.window_handles.should_not include(last_handle)
    end
  end

  it "preserves cookies across windows" do
    session_id = '12345'
    driver = driver_for_app do
      get '/new_window' do
        <<-HTML
          <html>
            <script type="text/javascript">
              window.open('http://#{request.host_with_port}/set_cookie');
            </script>
          </html>
        HTML
      end

      get '/set_cookie' do
        response.set_cookie 'session_id', session_id
      end
    end

    driver.visit("/new_window")
    driver.cookies['session_id'].should == session_id
  end

  context "timers app" do
    let(:driver) do
      driver_for_app do
        get "/success" do
          '<html><body></body></html>'
        end

        get "/not-found" do
          404
        end

        get "/outer" do
          <<-HTML
            <html>
              <head>
                <script>
                  function emit_true_load_finished(){var divTag = document.createElement("div");divTag.innerHTML = "<iframe src='/success'></iframe>";document.body.appendChild(divTag);};
                  function emit_false_load_finished(){var divTag = document.createElement("div");divTag.innerHTML = "<iframe src='/not-found'></iframe>";document.body.appendChild(divTag);};
                  function emit_false_true_load_finished() { emit_false_load_finished(); setTimeout('emit_true_load_finished()',100); };
                </script>
              </head>
              <body onload="setTimeout('emit_false_true_load_finished()',100)">
              </body>
            </html>
          HTML
        end

        get '/' do
          "<html><body></body></html>"
        end
      end
    end

    before { driver.visit("/") }

    it "raises error for any loadFinished failure" do
      expect do
        driver.visit("/outer")
        sleep 1
        driver.find("//body")
      end.to raise_error(Capybara::Webkit::InvalidResponseError)
    end
  end

  describe "basic auth" do
    let(:driver) do
      driver_for_app do
        get "/" do
          if env["HTTP_AUTHORIZATION"]
            env["HTTP_AUTHORIZATION"]
          else
            headers "WWW-Authenticate" => 'Basic realm="Secure Area"'
            status 401
            "401 Unauthorized."
          end
        end
      end
    end

    it "can authenticate a request" do
      driver.browser.authenticate('user', 'password')
      driver.visit("/")
      driver.body.should include("Basic "+Base64.encode64("user:password").strip)
    end
  end

  describe "timeout for long requests" do
    let(:driver) do
      driver_for_app do
        html = <<-HTML
            <html>
              <body>
                <form action="/form" method="post">
                  <input type="submit" value="Submit"/>
                </form>
              </body>
            </html>
        HTML

        get "/" do
          sleep(2)
          html
        end

        post "/form" do
          sleep(4)
          html
        end
      end
    end

    it "should not raise a timeout error when zero" do
      driver.browser.timeout = 0
      lambda { driver.visit("/") }.should_not raise_error(Capybara::TimeoutError)
    end

    it "should raise a timeout error" do
      driver.browser.timeout = 1
      lambda { driver.visit("/") }.should raise_error(Capybara::TimeoutError, "Request timed out after 1 second")
    end

    it "should not raise an error when the timeout is high enough" do
      driver.browser.timeout = 10
      lambda { driver.visit("/") }.should_not raise_error(Capybara::TimeoutError)
    end

    it "should set the timeout for each request" do
      driver.browser.timeout = 10
      lambda { driver.visit("/") }.should_not raise_error(Capybara::TimeoutError)
      driver.browser.timeout = 1
      lambda { driver.visit("/") }.should raise_error(Capybara::TimeoutError)
    end

    it "should set the timeout for each request" do
      driver.browser.timeout = 1
      lambda { driver.visit("/") }.should raise_error(Capybara::TimeoutError)
      driver.reset!
      driver.browser.timeout = 10
      lambda { driver.visit("/") }.should_not raise_error(Capybara::TimeoutError)
    end

    it "should raise a timeout on a slow form" do
      driver.browser.timeout = 3
      driver.visit("/")
      driver.status_code.should == 200
      driver.browser.timeout = 1
      driver.find("//input").first.click
      lambda { driver.status_code }.should raise_error(Capybara::TimeoutError)
    end

    it "get timeout" do
      driver.browser.timeout = 10
      driver.browser.timeout.should == 10
      driver.browser.timeout = 3
      driver.browser.timeout.should == 3
    end
  end

  describe "logger app" do
    it "logs nothing before turning on the logger" do
      driver.visit("/")
      log.should == ""
    end

    it "logs its commands after turning on the logger" do
      driver.enable_logging
      driver.visit("/")
      log.should_not == ""
    end

    let(:driver) do
      command = "#{Capybara::Webkit::Connection::SERVER_PATH} 2>&1"
      connection = Capybara::Webkit::Connection.new(:command => command, :stdout => output)
      browser = Capybara::Webkit::Browser.new(connection)
      Capybara::Webkit::Driver.new(AppRunner.app, :browser => browser)
    end

    let(:output) { StringIO.new }

    def log
      output.rewind
      output.read
    end
  end

  def driver_url(driver, path)
    URI.parse(driver.current_url).merge(path).to_s
  end
end
