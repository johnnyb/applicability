# Copyright 2007 New Medio.  This file is part of Applicability.  See README for additional information.                          
# TODO:
#  * Allow multiple area tags to be active at once
#  * Implement the remaining applicability controls
#  * Make this work with turning on/off table rows
#

module Applicability
  # This is a simple class which adapts the context class into the <tt>.rhtml</tt> file.
  module ApplicabilityHelper
    # This begins an applicability block.  The block is passed a single variable, which is
    # the "applicability context".  This function can take one parameter, which is the default
    # applicability area tag to activate.  This automatically handles outputting the javascript for you
    # at the end of the block.  Dummy is no longer used, but here for backwards compatibility.
    def applicability_begin(dummy = nil, &block)
      apc = ApplicabilityContext.new(self)
      if block_given?
        yield(apc)
        concat(apc.output_applicability_function, block.binding) 
      end

      return apc
    end
  end

  # This is the main context class.  You rarely instantiate this yourself - it is almost always
  # done through applicability_begin.
  class ApplicabilityContext
    include ActionView::Helpers::FormOptionsHelper
    include ActionView::Helpers::FormTagHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::JavaScriptHelper
    include ActionView::Helpers::TextHelper

    @@id_num = 1

    # view is used for rendering the output buffer
    def initialize(view)
      @areas = []
      @base_id = idgen
      @function_name = "reach_applic_#{@base_id}_func"
      @domains = []

      @view = view
    end

    # For new Rails versions
    def output_buffer
      @view.output_buffer
    end

    def output_buffer=(val)
      @view.output_buffer = val
    end

    # NOT YET IMPLEMENTED - will work like select_tag, but with the semantics of select
    def select
    end

    # NOT FINISHED/TESTED - this will link to an area tag to activate.
    def link_to(name, tag, *args)
      link_to_function(name, "document.#{@function_name}('#{args[0]}');", args)
    end

    # This is the main tag used to control the active area tag.  Takes several parameters:
    # [name] This is the HTML name for the select tag
    # [option_list] This is a list of options like what would be given to <tt>options_for_select</tt>.  
    #                 HOWEVER, these options take a middle parameter, where the middle parameter is the 
    #                 name of the area which should be shown if the option is selected. 
    # [options] This is just like the options for the regular <tt>select_tag</tt> function, except that
    #             it includes another option, <tt>:default</tt>, which is the default value for the select.
    #
    # If your <tt>option_list</tt> 
    # is <tt>[ ["Option One", :option_one, "one"], ["Option Two", :option_two, "two"]]</tt>, then if you 
    # select "Option One", that will set <tt>:option_one</tt> as the active area tag, and the value passed 
    # in the form will be "one".
    #
    def select_tag(name, option_list, options = {})
      domain_name = name
      
      #Determine default
      options[:id] ||= idgen
      default_key = options.delete(:default)
      default_applic = nil
      default_idx = nil
      option_list.each_index do |opt_idx| 
        if option_list[opt_idx].last == default_key 
          if default_idx.nil? #Use the _first_ one found
            default_idx = opt_idx
          end
        end
      end
      if default_idx.nil?
        default_idx = 0
      end
      default_applics = option_list[default_idx].nil? ? [] : [option_list[default_idx][1]]
      
      #Save Default for later
      @domains.push(:name => domain_name, :default_applics => default_applics)
      
      #Create function for running this applicability
      statements = option_list.map{|opt| "if(elem.options[elem.selectedIndex].value == '#{opt.last}') { document.#{@function_name}('set', '#{domain_name}', '#{opt[1]}'); }"}
      selection_function_name = "applic_select_#{idgen}_func"
      selection_function = "document.#{selection_function_name} = function(elem) { #{statements.join("\n")} };"
      onchange_action = "#{selection_function_name}(this); #{options[:onchange]}"
      
      #Create actual select tag and return it
      return super(name, options_for_select(option_list, default_key), options.merge(:onchange => onchange_action)) + javascript_tag(selection_function)
    end

    def domain_update(domain_name, applicable_value, checked)
      #Create domain / determine default 
      #(note that domain may already have been created)
      found_domain = false
      @domains.each do |domain|
        if domain[:name] == domain_name
          found_domain = true
          if checked
            domain[:default_applics] ||= []
            domain[:default_applics].push(applicable_value)
          end
        end
      end
      unless found_domain
        @domains.push(:name => domain_name, :default_applics => (checked ? [applicable_value] : []))
      end      
    end
    
    def radio_button_tag(name, applicable_value, value, checked=false, options={})
      #Create Javascript
      options[:id] ||= idgen
      domain_name = name
      onclick_action = "document.#{@function_name}('set', '#{domain_name}', '#{applicable_value}'); #{options[:onclick]}"
      
      domain_update(domain_name, applicable_value, checked)
      
      return super(name, value, checked, options.merge({:onclick => onclick_action}))
    end
    
    def check_box_tag(name, applicable_value, value, checked=false, options = {})
      #Create Javascript
      options[:id] ||= idgen
      domain_name = name
      onclick_action = "document.#{@function_name}(($('#{options[:id]}').checked ? 'add' : 'remove'), '#{domain_name}', '#{applicable_value}'); #{options[:onclick]}"

      domain_update(domain_name, applicable_value, checked)
      
      return super(name, value, checked, options.merge({:onclick => onclick_action}))
    end


    def applies_to(area_type, *application_list, &block)
      applies_to_full(area_type, :any, *application_list, &block)
    end
    
    def applies_to_all(area_type, *application_list, &block)
      applies_to_full(area_type, :all, *application_list, &block)
    end
    
    # This function creates areas that are turned on and off by the select, checkbox, and link functions.
    # The parameters are:
    # [area_type] This is usually either <tt>:span</tt> or <tt>:div</tt>.  It treats everything except <tt>:span</tt> as a block-level element.  Soon we will get it to work with table-stuff, too.
    # [application_list] You can send as many area tags that you want, and if any of them are selected, this area will be active.  Note that this does not take a list, but instead just pass them each individually.
    #
    # See the README for an example of how to use this in an <tt>.rhtml</tt> file.
    #
    def applies_to_full(area_type, area_mode, *application_list, &block)
      area_id = idgen

      area_display_type = area_type == :span ? "inline" : "block"

      unless area_mode == :ignore
        @areas.push({ :applicabilities => application_list, :type => area_type, :id => area_id, :display => area_display_type, :mode => area_mode })
      end

      content1 = "<#{area_type} id='#{area_id}'>"
      content2 = "</#{area_type}>"
      concat(content1, block.binding)
      yield
      concat(content2, block.binding)
    end
    
    

    # This is the name of the function that will be used to control the active applicability tag.
    def applicability_function_name
      @function_name
    end

    # This actually generates and spits out the function to control the <tt>applies_to</tt> sections
    # based on the active area tag.  If you use the <tt>applicability_begin</tt> helper, you will
    # never need to use this function.
    def output_applicability_function
      #NOTE - checking for the prototype instead of the Prototype version in case we've already made this change.
      js_check_compatibility = <<END_OF_OUTPUT
if(!Hash.prototype.get) {
  Hash.prototype.get = function(val) {
    return this[val];
  }

  Hash.prototype.set = function(key, val) {
    this[key] = val;
    return val;
  }
}
END_OF_OUTPUT
      
      js_basic_functions = <<END_OF_OUTPUT
var reach_applic_info_#{@base_id} = new Hash();
var reach_applic_ids_#{@base_id} = new Hash();
var reach_applic_id_combine_modes_#{@base_id} = new Hash();

document.reach_applic_#{@base_id}_func = function(mode, domain, applic_name) {
  /* Modify Global Applicability List */
  domain_val = reach_applic_info_#{@base_id}.get(domain);
  if(mode == 'add') {
    if(!domain_val) {
      reach_applic_info_#{@base_id}.set(domain, new Array());
    }
    domain_val.push(applic_name);
  } else if(mode == 'remove') {
    reach_applic_info_#{@base_id}.set(domain, domain_val.without(applic_name));
  } else if(mode == 'set') {
    reach_applic_info_#{@base_id}.set(domain, applic_name);
  } else {
    window.alert('Invalid mode');
  }

  document.reach_applic_#{@base_id}_show_applicable();
}

document.reach_applic_#{@base_id}_show_applicable = function() {
  /* Get official list of applicability names */
  applics = reach_applic_info_#{@base_id}.values().flatten();
    
  reach_applic_ids_#{@base_id}.each(function(id_info) {
    elem_id = id_info[0];
    val_array = id_info[1];
    should_show = true;
    current_mode = reach_applic_id_combine_modes_#{@base_id}.get(elem_id);
    if(current_mode == 'all') {
      /* all */
      val_array.each(function(item) {
        if(applics.indexOf(item) == -1) {
          should_show = false;
        }
      });
    } else if(current_mode == 'any') {
      /* any */
      should_show = false;
      val_array.each(function(item) {
        if(applics.indexOf(item) != -1) {
          should_show = true;
        }
      });
    } else if(current_mode == 'none') {
      /* none */
      should_show = true;
      val_array.each(function(item) {
        if(applics.indexOf(item) != -1) {
          should_show = false;
        }
      });
    } else {
      window.alert("Unknown combine mode.");
    }

    if(should_show) {
      $(elem_id).style.display = 'block';
    } else {
      $(elem_id).style.display = 'none';
    }
  });
}
END_OF_OUTPUT
      
      #FIXME - current implementation of defaults does not survive reloads, need to instead read the defaults from the form
      #        itself to make sure that we are getting the right stuff.
      
      js_area_applics = @areas.map{|area| "reach_applic_ids_#{@base_id}.set('#{area[:id]}', ['#{area[:applicabilities].join("','")}']);\n"}.join("")
      js_area_types = @areas.map{|area| "reach_applic_id_combine_modes_#{@base_id}.set('#{area[:id]}', '#{area[:mode]}');\n"}.join("")
      js_default_applics = @domains.map{|domain| "reach_applic_info_#{@base_id}.set('#{domain[:name]}', [#{domain[:default_applics].map{|x| "'#{x}'"}.join(",")}]);\n"}.join("")
      js_set_default_showing = "document.reach_applic_#{@base_id}_show_applicable();"
      js_output = js_check_compatibility + js_basic_functions + js_area_applics + js_default_applics + js_area_types + js_set_default_showing
      return javascript_tag(js_output)
    end

    private
    def idgen
      @@id_num += 1
      "aplic#{@@id_num}"
    end

  end
end
