CLASS zcl_abapgit_ecatt_script_downl DEFINITION
  PUBLIC
  INHERITING FROM cl_apl_ecatt_script_download
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS:
      download REDEFINITION,

      get_xml_stream
        RETURNING
          VALUE(rv_xml_stream) TYPE xstring,

      get_xml_stream_size
        RETURNING
          VALUE(rv_xml_stream_size) TYPE int4.

  PROTECTED SECTION.
    METHODS:
      download_data REDEFINITION.

  PRIVATE SECTION.
    DATA:
      mv_xml_stream      TYPE xstring,
      mv_xml_stream_size TYPE int4,
      mv_script_node     TYPE REF TO if_ixml_element.

    METHODS:
      set_script_to_template
        RAISING
          cx_ecatt_apl_util,

      set_control_data_for_tcd
        IMPORTING
          is_param  TYPE etpar_gui
          ip_params TYPE REF TO cl_apl_ecatt_params
        RAISING
          cx_ecatt_apl,

      escape_control_data
        IMPORTING
          ip_element TYPE REF TO if_ixml_element
          im_tabname TYPE string
          im_node    TYPE string
        RAISING
          cx_ecatt_apl_util,

      set_blob_to_template
        RAISING
          cx_ecatt_apl_util,

      set_artmp_to_template
        RAISING
          cx_ecatt_apl_util.

ENDCLASS.


CLASS zcl_abapgit_ecatt_script_downl IMPLEMENTATION.

  METHOD download.

    " Downport

    DATA: lv_partyp TYPE string,
          lx_ecatt  TYPE REF TO cx_ecatt_apl.

    load_help = im_load_help.
    typ = im_object_type.

    TRY.
        cl_apl_ecatt_object=>show_object(
          EXPORTING
            im_obj_type = im_object_type
            im_name     = im_object_name
            im_version  = im_object_version
          IMPORTING
            re_object   = ecatt_object ).
      CATCH cx_ecatt INTO ex_ecatt.
        RETURN.
    ENDTRY.

    toolname = ecatt_object->attrib->get_tool_name( ).
* build_schema( ).
* set_attributes_to_schema( ).
    set_attributes_to_template( ).

    IF toolname EQ cl_apl_ecatt_const=>toolname_ecatt.

      ecatt_script ?= ecatt_object.

*   set_script_to_schema( ).
      set_script_to_template( ).

*   set_params_to_schema( ).
      TRY.
          get_general_params_data( im_params = ecatt_script->params ).
        CATCH cx_ecatt_apl INTO lx_ecatt.                "#EC NOHANDLER
*         proceed with download and report errors later
      ENDTRY.

      LOOP AT parm INTO wa_parm.
        TRY.
            IF wa_parm-value = '<INITIAL>'.
              CLEAR wa_parm-value.
            ENDIF.
            set_general_params_data_to_dom( ).
            IF NOT wa_parm-pstruc_typ IS INITIAL.
              set_deep_stru_to_dom( ecatt_script->params ).
              set_deep_data_to_dom( im_params = ecatt_script->params ).
              IF wa_parm-xmlref_typ EQ cl_apl_ecatt_const=>ref_type_c_tcd.
                set_control_data_for_tcd( is_param  =  wa_parm
                                          ip_params = ecatt_script->params ).

              ENDIF.
            ENDIF.
          CATCH cx_ecatt_apl INTO lx_ecatt.              "#EC NOHANDLER
*         proceed with download and report errors later
        ENDTRY.
      ENDLOOP.

    ELSE.

      set_blob_to_template( ).
      set_artmp_to_template( ).

    ENDIF.

* download_schema( ).
    download_data( ).

  ENDMETHOD.


  METHOD download_data.

    " Downport

    zcl_abapgit_ecatt_helper=>download_data(
      EXPORTING
        ii_template_over_all = template_over_all
      IMPORTING
        ev_xml_stream        = mv_xml_stream
        ev_xml_stream_size   = mv_xml_stream_size ).

  ENDMETHOD.


  METHOD get_xml_stream.

    rv_xml_stream = mv_xml_stream.

  ENDMETHOD.


  METHOD get_xml_stream_size.

    rv_xml_stream_size = mv_xml_stream_size.

  ENDMETHOD.


  METHOD set_script_to_template.

    " Downport

    DATA:
      lv_text    TYPE etxml_line_tabtype,
      li_element TYPE REF TO if_ixml_element,
      lv_rc      TYPE sy-subrc.

    ecatt_script->get_script_text(
      CHANGING
        scripttext = lv_text ).

    mv_script_node = template_over_all->create_simple_element(
                        name = 'SCRIPT'
                        parent = root_node ).

    IF mv_script_node IS INITIAL.
      me->raise_download_exception(
            textid        = cx_ecatt_apl_util=>download_processing
            previous      = ex_ecatt
            called_method = 'CL_APL_ECATT_SCRIPT_DOWNLOAD->SET_SCRIPT_TO_TEMPLATE' ) .
    ENDIF.

    CALL FUNCTION 'SDIXML_DATA_TO_DOM'
      EXPORTING
        name         = 'ETXML_LINE_TABTYPE'
        dataobject   = lv_text
      IMPORTING
        data_as_dom  = li_element
      CHANGING
        document     = template_over_all
      EXCEPTIONS
        illegal_name = 1
        OTHERS       = 2.
    IF sy-subrc <> 0.
      me->raise_download_exception(
            textid        = cx_ecatt_apl_util=>download_processing
            previous      = ex_ecatt
            called_method = 'CL_APL_ECATT_SCRIPT_DOWNLOAD->SET_SCRIPT_TO_TEMPLATE' ).

    ENDIF.

    lv_rc = mv_script_node->append_child( li_element ).
    IF lv_rc <> 0.
      me->raise_download_exception(
            textid        = cx_ecatt_apl_util=>download_processing
            previous      = ex_ecatt
            called_method = 'CL_APL_ECATT_SCRIPT_DOWNLOAD->SET_SCRIPT_TO_TEMPLATE' ).
    ENDIF.

  ENDMETHOD.


  METHOD set_control_data_for_tcd.

    " Downport

    DATA: lt_params TYPE ettcd_params_tabtype,
          lt_verbs  TYPE ettcd_verbs_tabtype,
          lt_vars   TYPE ettcd_vars_tabtype,
          lt_dp_tab TYPE ettcd_dp_tab_tabtype,
          lt_dp_for TYPE ettcd_dp_for_tabtype,
          lt_dp_pro TYPE ettcd_dp_pro_tabtype,
          lt_dp_fld TYPE ettcd_dp_fld_tabtype,
          lt_svars  TYPE ettcd_svars_tabtype.

    DATA: li_element   TYPE REF TO if_ixml_element,
          li_deep_tcd  TYPE REF TO if_ixml_element,
          lv_rc        TYPE sy-subrc,
          lt_name      TYPE string,
          lv_parname   TYPE string,
          lo_pval_xml  TYPE REF TO cl_apl_ecatt_xml_data,
          lo_ctrl_tabs TYPE REF TO cl_apl_ecatt_control_tables.

    FIELD-SYMBOLS: <tab> TYPE STANDARD TABLE.

    IF is_param-xmlref_typ <> cl_apl_ecatt_const=>ref_type_c_tcd
      OR  ip_params IS INITIAL.
      RETURN.
    ENDIF.

    lv_parname = is_param-pname.

    ip_params->get_param_value(     "TCD command interface
      EXPORTING
        im_var_id   = cl_apl_ecatt_const=>varid_default_val
        im_pname    = lv_parname
        im_pindex   = is_param-pindex
      IMPORTING
        ex_pval_xml = lo_pval_xml ).

    lo_ctrl_tabs = lo_pval_xml->get_control_tables_ref( ).
    IF lo_ctrl_tabs IS INITIAL.
      RETURN.
    ENDIF.

    lo_ctrl_tabs->get_control_tables(          "Read 8 control tables
      IMPORTING
        ex_params = lt_params
        ex_verbs  = lt_verbs
        ex_vars   = lt_vars
        ex_dp_tab = lt_dp_tab
        ex_dp_for = lt_dp_for
        ex_dp_pro = lt_dp_pro
        ex_dp_fld = lt_dp_fld
        ex_svars  = lt_svars ).

    IF lt_params IS INITIAL OR
       lt_verbs  IS INITIAL OR
       lt_vars   IS INITIAL OR
       lt_dp_tab IS INITIAL OR
       lt_dp_for IS INITIAL OR
       lt_dp_pro IS INITIAL OR
       lt_dp_fld IS INITIAL OR
       lt_svars  IS INITIAL.

      RETURN.
    ENDIF.

    li_deep_tcd = template_over_all->create_simple_element_ns(
                    name   = cl_apl_xml_const=>upl_tcd_node
                    parent = ap_current_param ).

    IF li_deep_tcd IS INITIAL.
      raise_download_exception(
            textid   = cx_ecatt_apl_util=>download_processing
            previous = ex_ecatt ).
    ENDIF.

    DO 8 TIMES.                                "Loop at 8 control tables
      CASE sy-index.
        WHEN 1.
          lt_name = 'ETTCD_PARAMS_TABTYPE'.
          ASSIGN lt_params TO <tab>.
        WHEN 2.
          lt_name = 'ETTCD_VERBS_TABTYPE'.
          ASSIGN lt_verbs TO <tab>.
        WHEN 3.
          lt_name = 'ETTCD_VARS_TABTYPE'.
          ASSIGN lt_vars TO <tab>.
        WHEN 4.
          lt_name = 'ETTCD_DP_TAB_TABTYPE'.
          ASSIGN lt_dp_tab TO <tab>.
        WHEN 5.
          lt_name = 'ETTCD_DP_FOR_TABTYPE'.
          ASSIGN lt_dp_for TO <tab>.
        WHEN 6.
          lt_name = 'ETTCD_DP_PRO_TABTYPE'.
          ASSIGN lt_dp_pro TO <tab>.
        WHEN 7.
          lt_name = 'ETTCD_DP_FLD_TABTYPE'.
          ASSIGN lt_dp_fld TO <tab>.
        WHEN 8.
          lt_name = 'ETTCD_SVARS_TABTYPE'.
          ASSIGN lt_svars TO <tab>.
      ENDCASE.

      CALL FUNCTION 'SDIXML_DATA_TO_DOM'       "Ast generieren lassen
        EXPORTING
          name         = lt_name
          dataobject   = <tab>
        IMPORTING
          data_as_dom  = li_element
        EXCEPTIONS
          illegal_name = 1
          OTHERS       = 2.

      IF sy-subrc <> 0.
        me->raise_download_exception(
              textid   = cx_ecatt_apl_util=>download_processing
              previous = ex_ecatt ).
      ENDIF.

* Ast in Hauptbaum haengen
      lv_rc = li_deep_tcd->append_child( new_child = li_element ).

      IF lv_rc <> 0.
        me->raise_download_exception(
              textid   = cx_ecatt_apl_util=>download_processing
              previous = ex_ecatt ).
      ENDIF.
      FREE li_element.
      UNASSIGN <tab>.
    ENDDO.

    escape_control_data( ip_element = li_deep_tcd
      im_tabname = 'ETTCD_VARS_TABTYPE'
      im_node    = 'CB_INDEX' ).

    escape_control_data(
      ip_element = li_deep_tcd
      im_tabname = 'ETTCD_VERBS_TABTYPE'
      im_node    = 'NAME' ).

    FREE: lt_dp_tab, lt_dp_for, lt_dp_fld, lt_svars,
          lt_params, lt_vars,   lt_dp_pro, lt_verbs.

  ENDMETHOD.


  METHOD escape_control_data.

    " Downport

    DATA: li_iter     TYPE REF TO if_ixml_node_iterator,
          li_textit   TYPE REF TO if_ixml_node_iterator,
          li_abapctrl TYPE REF TO if_ixml_node_collection,
          li_text     TYPE REF TO if_ixml_text,
          li_filter   TYPE REF TO if_ixml_node_filter,
          li_list     TYPE REF TO if_ixml_node_list,
          lv_value    TYPE etdom_name,
          li_vars     TYPE REF TO if_ixml_element,
          li_elem     TYPE REF TO if_ixml_element.

    li_vars = ip_element->find_from_name_ns(
    name = im_tabname ).
    li_filter = ip_element->create_filter_node_type(
    if_ixml_node=>co_node_text ).
    IF li_vars IS NOT INITIAL.
      li_abapctrl = ip_element->get_elements_by_tag_name_ns( name = im_node ).

* just for debugging
      li_iter = li_abapctrl->create_iterator( ).
      li_elem ?= li_iter->get_next( ).
      WHILE li_elem IS NOT INITIAL.
        li_list = li_elem->get_children( ).

        li_textit = li_list->create_rev_iterator_filtered(
        filter = li_filter  ).
        li_text ?= li_textit->get_next( ).
        IF li_text IS NOT INITIAL.
          lv_value = li_text->get_data( ).
          IF lv_value(1) =  cl_abap_char_utilities=>minchar.
            REPLACE SECTION OFFSET 0 LENGTH 1 OF lv_value WITH space.
            li_text->set_value( value = lv_value ).
          ENDIF.
        ENDIF.
        CLEAR: li_textit, li_list, li_elem, lv_value.
        li_elem ?= li_iter->get_next( ).
      ENDWHILE.
      CLEAR: li_abapctrl, li_elem, li_iter.

    ENDIF.

  ENDMETHOD.


  METHOD set_blob_to_template.

    " Downport

    DATA: blob_node TYPE REF TO if_ixml_element,
          rc        TYPE sy-subrc,
          text      TYPE string.

    blob_node = template_over_all->create_simple_element(
                  name   = 'ECET_BLOBS'
                  parent = root_node ).

    IF blob_node IS INITIAL.
      me->raise_download_exception(
            textid        = cx_ecatt_apl_util=>download_processing
            previous      = ex_ecatt
            called_method = 'CL_APL_ECATT_SCRIPT_DOWNLOAD->SET_BLOB_TO_TEMPLATE' ).
    ENDIF.

    ecatt_extprog->get_blob(
      EXPORTING
        im_whole_data = 1
      IMPORTING
        ex_xml_blob   = text ).

    rc = blob_node->set_value( value = text ).
    IF rc <> 0.
      me->raise_download_exception(
            textid        = cx_ecatt_apl_util=>download_processing
            previous      = ex_ecatt
            called_method = 'CL_APL_ECATT_SCRIPT_DOWNLOAD->SET_BLOB_TO_TEMPLATE' ).
    ENDIF.

  ENDMETHOD.                    "SET_BLOB_TO_TEMPLATE


  METHOD set_artmp_to_template.

    " Downport

    DATA: li_artmp_node TYPE REF TO if_ixml_element,
          lv_rc         TYPE sy-subrc,
          lv_text       TYPE string,
          l_rc          TYPE int4,
          lv_errmsg     TYPE string.

    li_artmp_node = template_over_all->create_simple_element(
                      name   = 'ECET_ARTMP'
                      parent = root_node ).

    ecatt_extprog->get_args_tmpl(
      IMPORTING
        ex_xml_arg_tmpl = lv_text
        ex_rc           = l_rc
        ex_errmsg       = lv_errmsg ).

    IF li_artmp_node IS INITIAL OR l_rc > 0.
      me->raise_download_exception(
          textid        = cx_ecatt_apl_util=>download_processing
          previous      = ex_ecatt
          called_method = 'CL_APL_ECATT_SCRIPT_DOWNLOAD->SET_ARTMP_TO_TEMPLATE'
          free_text     = lv_errmsg ).
    ENDIF.

    lv_rc = li_artmp_node->set_value( value = lv_text ).
    IF lv_rc <> 0.
      me->raise_download_exception(
            textid        = cx_ecatt_apl_util=>download_processing
            previous      = ex_ecatt
            called_method = 'CL_APL_ECATT_SCRIPT_DOWNLOAD->SET_ARTMP_TO_TEMPLATE' ).
    ENDIF.

  ENDMETHOD.

ENDCLASS.