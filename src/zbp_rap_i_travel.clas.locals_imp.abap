class lhc_Travel definition inheriting from cl_abap_behavior_handler.
  private section.

    constants:
      begin of travel_status,
        open     type c length 1  value 'O', " Open
        accepted type c length 1  value 'A', " Accepted
        canceled type c length 1  value 'X', " Cancelled
      end of travel_status.

    methods get_instance_features for instance features
      importing keys request requested_features for Travel result result.

    methods acceptTravel for modify
      importing keys for action Travel~acceptTravel result result.

    methods recalcTotalPrice for modify
      importing keys for action Travel~recalcTotalPrice.

    methods rejectTravel for modify
      importing keys for action Travel~rejectTravel result result.

    methods calculateTotalPrice for determine on modify
      importing keys for Travel~calculateTotalPrice.

    methods setInitialStatus for determine on modify
      importing keys for Travel~setInitialStatus.

    methods calculateTravelID for determine on save
      importing keys for Travel~calculateTravelID.

    methods validateAgency for validate on save
      importing keys for Travel~validateAgency.

    methods validateCustomer for validate on save
      importing keys for Travel~validateCustomer.

    methods validateDates for validate on save
      importing keys for Travel~validateDates.

    methods get_instance_authorizations for instance authorization
      importing keys request requested_authorizations for Travel result result.

    methods is_update_granted importing has_before_image      type abap_bool
                                        overall_status        type /dmo/overall_status
                              returning value(update_granted) type abap_bool.

    methods is_delete_granted importing has_before_image      type abap_bool
                                        overall_status        type /dmo/overall_status
                              returning value(delete_granted) type abap_bool.

    methods is_create_granted returning value(create_granted) type abap_bool.

endclass.

class lhc_Travel implementation.

  method acceptTravel.

    " Set the new overall status
    modify entities of zrap_i_travel in local mode
      entity Travel
         update
           fields ( TravelStatus )
           with value #( for key in keys
                           ( %tky         = key-%tky "->Transactional Key
                             TravelStatus = travel_status-accepted ) )
      failed failed
      reported reported.

    " Fill the response table
    read entities of zrap_i_travel in local mode
      entity Travel
        all fields with corresponding #( keys )
      result data(travels).

    result = value #( for travel in travels
                        ( %tky   = travel-%tky "->Transactional Key
                          %param = travel ) ).

  endmethod.

  method rejectTravel.

    " Set the new overall status
    modify entities of zrap_i_travel in local mode
      entity Travel
         update
           fields ( TravelStatus )
           with value #( for key in keys
                           ( %tky         = key-%tky
                             TravelStatus = travel_status-canceled ) )
      failed failed
      reported reported.

    " Fill the response table
    read entities of zrap_i_travel in local mode
      entity Travel
        all fields with corresponding #( keys )
      result data(travels).

    result = value #( for travel in travels
                        ( %tky   = travel-%tky
                          %param = travel ) ).

  endmethod.

  method calculateTravelID.
    " Please note that this is just an example for calculating a field during onSave.
    " This approach does NOT ensure for gap free or unique travel IDs! It just helps to provide a readable ID.
    " The key of this business object is a UUID, calculated by the framework.

    " check if TravelID is already filled
    read entities of zrap_i_travel in local mode
      entity Travel
        fields ( TravelID ) with corresponding #( keys )
      result data(travels).

    " remove lines where TravelID is already filled.
    delete travels where TravelID is not initial.

    " anything left ?
    check travels is not initial.

    " Select max travel ID
    select single
        from  zrap_t_travel
        fields max( travel_id ) as travelID
        into @data(max_travelid).

    " Set the travel ID
    modify entities of zrap_i_travel in local mode
    entity Travel
      update
        from value #( for travel in travels index into i (
          %tky              = travel-%tky
          TravelID          = max_travelid + i
          %control-TravelID = if_abap_behv=>mk-on ) )
    reported data(update_reported).

    reported = corresponding #( deep update_reported ).
  endmethod.

  method setInitialStatus.
    " Read relevant travel instance data
    read entities of zrap_i_travel in local mode
      entity Travel
        fields ( TravelStatus ) with corresponding #( keys )
      result data(travels).

    " Remove all travel instance data with defined status
    delete travels where TravelStatus is not initial.
    check travels is not initial.

    " Set default travel status
    modify entities of zrap_i_travel in local mode
    entity Travel
      update
        fields ( TravelStatus )
        with value #( for travel in travels
                      ( %tky         = travel-%tky
                        TravelStatus = travel_status-open ) )
    reported data(update_reported).

    reported = corresponding #( deep update_reported ).
  endmethod.

  method validateAgency.
    " Read relevant travel instance data
    read entities of zrap_i_travel in local mode
      entity Travel
        fields ( AgencyID ) with corresponding #( keys )
      result data(travels).

    data agencies type sorted table of /dmo/agency with unique key agency_id.

    " Optimization of DB select: extract distinct non-initial agency IDs
    agencies = corresponding #( travels discarding duplicates mapping agency_id = AgencyID except * ).
    delete agencies where agency_id is initial.

*    if agencies is not initial.
*      " Check if agency ID exist
*      select from /dmo/agency fields agency_id
*        for all entries in @agencies
*        where agency_id = @agencies-agency_id
*        into table @data(agencies_db).
*    endif.


    " Raise msg for non existing and initial agencyID
    loop at travels into data(travel).
      " Clear state messages that might exist
      append value #(  %tky               = travel-%tky
                       %state_area        = 'VALIDATE_AGENCY' )
        to reported-travel.

*      if travel-AgencyID is initial or not line_exists( agencies_db[ agency_id = travel-AgencyID ] ).
*        append value #( %tky = travel-%tky ) to failed-travel.
*
*        append value #( %tky        = travel-%tky
*                        %state_area = 'VALIDATE_AGENCY'
*                        %msg        = new zrap_cm(
*                                          severity = if_abap_behv_message=>severity-error
*                                          textid   = zrap_cm=>agency_unknown
*                                          agencyid = travel-AgencyID )
*                        %element-AgencyID = if_abap_behv=>mk-on )
*          to reported-travel.
*      endif.
    endloop.

    DATA filter_conditions  TYPE if_rap_query_filter=>tt_name_range_pairs .
    DATA ranges_table TYPE if_rap_query_filter=>tt_range_option .
    DATA business_data TYPE TABLE OF zsc_rap_agency=>tys_z_travel_agency_es_5_type.
    IF  agencies IS NOT INITIAL.
      ranges_table = VALUE #( FOR agency IN agencies (  sign = 'I' option = 'EQ' low = agency-agency_id ) ).
      filter_conditions = VALUE #( ( name = 'AGENCYID'  range = ranges_table ) ).
      TRY.
          "skip and top must not be used
          "but an appropriate filter will be provided
         NEW zcl_ce_rap_agency( )->get_agencies(
            EXPORTING
              filter_cond    = filter_conditions
              is_data_requested  = abap_true
              is_count_requested = abap_false
            IMPORTING
              business_data  = business_data
            ) .
        CATCH /iwbep/cx_cp_remote
              /iwbep/cx_gateway
              cx_web_http_client_error
              cx_http_dest_provider_error INTO DATA(exception).
          DATA(exception_message) = cl_message_helper=>get_latest_t100_exception( exception )->if_message~get_text( ) .
          "Raise msg for problems calling the remote OData service
          LOOP AT travels INTO travel WHERE AgencyID IN ranges_table.
            APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
            APPEND VALUE #( %tky        = travel-%tky
                            %state_area = 'VALIDATE_AGENCY'
                            %msg        =  new_message_with_text( severity = if_abap_behv_message=>severity-error text = exception_message )
                            %element-AgencyID = if_abap_behv=>mk-on )
              TO reported-travel.
          ENDLOOP.
          RETURN.
      ENDTRY.
    ENDIF.

    " Raise msg for non existing and initial agencyID
**    LOOP AT travels INTO DATA(travel).
    LOOP AT travels INTO travel.
**      " Clear state messages that might exist
**      APPEND VALUE #(  %tky               = travel-%tky
**                       %state_area        = 'VALIDATE_AGENCY' )
**        TO reported-travel.
**      IF travel-AgencyID IS INITIAL OR NOT line_exists( agencies_db[ agency_id = travel-AgencyID ] ).
      IF travel-AgencyID IS INITIAL OR NOT line_exists( business_data[ agency_id = travel-AgencyID ] ).
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky        = travel-%tky
                        %state_area = 'VALIDATE_AGENCY'
                        %msg        = NEW zrap_cm(
                                          severity = if_abap_behv_message=>severity-error
                                          textid   = zrap_cm=>agency_unknown
                                          agencyid = travel-AgencyID )
                        %element-AgencyID = if_abap_behv=>mk-on )
          TO reported-travel.
      ENDIF.
    ENDLOOP.

  endmethod.


  method validatecustomer.
    " Read relevant travel instance data
    read entities of zrap_i_travel in local mode
      entity Travel
        fields ( CustomerID ) with corresponding #( keys )
      result data(travels).

    data customers type sorted table of /dmo/customer with unique key customer_id.

    " Optimization of DB select: extract distinct non-initial customer IDs
    customers = corresponding #( travels discarding duplicates mapping customer_id = CustomerID except * ).
    delete customers where customer_id is initial.
    if customers is not initial.
      " Check if customer ID exist
      select from /dmo/customer fields customer_id
        for all entries in @customers
        where customer_id = @customers-customer_id
        into table @data(customers_db).
    endif.

    " Raise msg for non existing and initial customerID
    loop at travels into data(travel).
      " Clear state messages that might exist
      append value #(  %tky        = travel-%tky
                       %state_area = 'VALIDATE_CUSTOMER' )
        to reported-travel.

      if travel-CustomerID is initial or not line_exists( customers_db[ customer_id = travel-CustomerID ] ).
        append value #(  %tky = travel-%tky ) to failed-travel.

        append value #(  %tky        = travel-%tky
                         %state_area = 'VALIDATE_CUSTOMER'
                         %msg        = new zrap_cm(
                                           severity   = if_abap_behv_message=>severity-error
                                           textid     = zrap_cm=>customer_unknown
                                           customerid = travel-CustomerID )
                         %element-CustomerID = if_abap_behv=>mk-on )
          to reported-travel.
      endif.
    endloop.
  endmethod.


  method validateDates.
    read entities of zrap_i_travel in local mode
      entity Travel
        fields ( TravelID BeginDate EndDate ) with corresponding #( keys )
      result data(travels).

    loop at travels into data(travel).
      " Clear state messages that might exist
      append value #(  %tky        = travel-%tky
                       %state_area = 'VALIDATE_DATES' )
        to reported-travel.

      if travel-EndDate < travel-BeginDate.
        append value #( %tky = travel-%tky ) to failed-travel.
        append value #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = new zrap_cm(
                                                 severity  = if_abap_behv_message=>severity-error
                                                 textid    = zrap_cm=>date_interval
                                                 begindate = travel-BeginDate
                                                 enddate   = travel-EndDate
                                                 travelid  = travel-TravelID )
                        %element-BeginDate = if_abap_behv=>mk-on
                        %element-EndDate   = if_abap_behv=>mk-on ) to reported-travel.

      elseif travel-BeginDate < cl_abap_context_info=>get_system_date( ).
        append value #( %tky               = travel-%tky ) to failed-travel.
        append value #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = new zrap_cm(
                                                 severity  = if_abap_behv_message=>severity-error
                                                 textid    = zrap_cm=>begin_date_before_system_date
                                                 begindate = travel-BeginDate )
                        %element-BeginDate = if_abap_behv=>mk-on ) to reported-travel.
      endif.
    endloop.
  endmethod.

  method get_instance_features.
    " Read the travel status of the existing travels
    read entities of zrap_i_travel in local mode
      entity Travel
        fields ( TravelStatus ) with corresponding #( keys )
      result data(travels)
      failed failed.

    result =
      value #(
        for travel in travels
          let is_accepted =   cond #( when travel-TravelStatus = travel_status-accepted
                                      then if_abap_behv=>fc-o-disabled
                                      else if_abap_behv=>fc-o-enabled  )
              is_rejected =   cond #( when travel-TravelStatus = travel_status-canceled
                                      then if_abap_behv=>fc-o-disabled
                                      else if_abap_behv=>fc-o-enabled )
          in
            ( %tky                 = travel-%tky
              %action-acceptTravel = is_accepted
              %action-rejectTravel = is_rejected
             ) ).
  endmethod.

  method recalctotalprice.

    types: begin of ty_amount_per_currencycode,
             amount        type /dmo/total_price,
             currency_code type /dmo/currency_code,
           end of ty_amount_per_currencycode.

    data: amount_per_currencycode type standard table of ty_amount_per_currencycode.

    " Read all relevant travel instances.
    read entities of zrap_i_travel in local mode
         entity Travel
            fields ( BookingFee CurrencyCode )
            with corresponding #( keys )
         result data(travels).

    delete travels where CurrencyCode is initial.

    loop at travels assigning field-symbol(<travel>).
      " Set the start for the calculation by adding the booking fee.
      amount_per_currencycode = value #( ( amount        = <travel>-BookingFee
                                           currency_code = <travel>-CurrencyCode ) ).

      " Read all associated bookings and add them to the total price.
      read entities of zrap_i_travel in local mode
        entity Travel by \_Booking
          fields ( FlightPrice CurrencyCode )
        with value #( ( %tky = <travel>-%tky ) )
        result data(bookings).

      loop at bookings into data(booking) where CurrencyCode is not initial.
        collect value ty_amount_per_currencycode( amount        = booking-FlightPrice
                                                  currency_code = booking-CurrencyCode ) into amount_per_currencycode.
      endloop.

      clear <travel>-TotalPrice.
      loop at amount_per_currencycode into data(single_amount_per_currencycode).
        " If needed do a Currency Conversion
        if single_amount_per_currencycode-currency_code = <travel>-CurrencyCode.
          <travel>-TotalPrice += single_amount_per_currencycode-amount.
        else.
          /dmo/cl_flight_amdp=>convert_currency(
             exporting
               iv_amount                   =  single_amount_per_currencycode-amount
               iv_currency_code_source     =  single_amount_per_currencycode-currency_code
               iv_currency_code_target     =  <travel>-CurrencyCode
               iv_exchange_rate_date       =  cl_abap_context_info=>get_system_date( )
             importing
               ev_amount                   = data(total_booking_price_per_curr)
            ).
          <travel>-TotalPrice += total_booking_price_per_curr.
        endif.
      endloop.
    endloop.

    " write back the modified total_price of travels
    modify entities of zrap_i_travel in local mode
      entity travel
        update fields ( TotalPrice )
        with corresponding #( travels ).

  endmethod.

  method calculateTotalPrice.

    modify entities of zrap_i_travel in local mode
      entity travel
        execute recalcTotalPrice
        from corresponding #( keys )
      reported data(execute_reported).

    reported = corresponding #( deep execute_reported ).

  endmethod.

  method get_instance_authorizations.

    data: has_before_image    type abap_bool,
          is_update_requested type abap_bool,
          is_delete_requested type abap_bool,
          update_granted      type abap_bool,
          delete_granted      type abap_bool.

    data: failed_travel like line of failed-travel.

    " Read the existing travels
    read entities of zrap_i_travel in local mode
      entity Travel
        fields ( TravelStatus ) with corresponding #( keys )
      result data(travels)
      failed failed.

    check travels is not initial.

*   In this example the authorization is defined based on the Activity + Travel Status
*   For the Travel Status we need the before-image from the database. We perform this for active (is_draft=00) as well as for drafts (is_draft=01) as we can't distinguish between edit or new drafts
    select from zrap_t_travel
      fields travel_uuid,overall_status
      for all entries in @travels
      where travel_uuid eq @travels-TravelUUID
      order by primary key
      into table @data(travels_before_image).

    is_update_requested = cond #( when requested_authorizations-%update              = if_abap_behv=>mk-on or
                                       requested_authorizations-%action-acceptTravel = if_abap_behv=>mk-on or
                                       requested_authorizations-%action-rejectTravel = if_abap_behv=>mk-on or
                                       requested_authorizations-%action-Prepare      = if_abap_behv=>mk-on OR
                                       requested_authorizations-%action-Edit         = if_abap_behv=>mk-on OR
                                       requested_authorizations-%assoc-_Booking      = if_abap_behv=>mk-on
                                  then abap_true else abap_false ).

    is_delete_requested = cond #( when requested_authorizations-%delete = if_abap_behv=>mk-on
                                  then abap_true else abap_false ).

    loop at travels into data(travel).
      update_granted = delete_granted = abap_false.

      read table travels_before_image into data(travel_before_image)
       with key travel_uuid = travel-TravelUUID binary search.
      has_before_image = cond #( when sy-subrc = 0 then abap_true else abap_false ).

      if is_update_requested = abap_true.
        " Edit of an existing record -> check update authorization
        if has_before_image = abap_true.
          update_granted = is_update_granted( has_before_image = has_before_image  overall_status = travel_before_image-overall_status ).
          if update_granted = abap_false.
            append value #( %tky        = travel-%tky
                            %msg        = new zrap_cm( severity = if_abap_behv_message=>severity-error
                                                            textid   = zrap_cm=>unauthorized )
                          ) to reported-travel.
          endif.
          " Creation of a new record -> check create authorization
        else.
          update_granted = is_create_granted( ).
          if update_granted = abap_false.
            append value #( %tky        = travel-%tky
                            %msg        = new zrap_cm( severity = if_abap_behv_message=>severity-error
                                                            textid   = zrap_cm=>unauthorized )
                          ) to reported-travel.
          endif.
        endif.
      endif.

      if is_delete_requested = abap_true.
        delete_granted = is_delete_granted( has_before_image = has_before_image  overall_status = travel_before_image-overall_status ).
        if delete_granted = abap_false.
          append value #( %tky        = travel-%tky
                          %msg        = new zrap_cm( severity = if_abap_behv_message=>severity-error
                                                          textid   = zrap_cm=>unauthorized )
                        ) to reported-travel.
        endif.
      endif.

      append value #( %tky = travel-%tky

                      %update              = cond #( when update_granted = abap_true then if_abap_behv=>auth-allowed else if_abap_behv=>auth-unauthorized )
                      %action-acceptTravel = cond #( when update_granted = abap_true then if_abap_behv=>auth-allowed else if_abap_behv=>auth-unauthorized )
                      %action-rejectTravel = cond #( when update_granted = abap_true then if_abap_behv=>auth-allowed else if_abap_behv=>auth-unauthorized )
                      %action-Prepare      = COND #( WHEN update_granted = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized )
                      %action-Edit         = COND #( WHEN update_granted = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized )
                      %assoc-_Booking      = cond #( when update_granted = abap_true then if_abap_behv=>auth-allowed else if_abap_behv=>auth-unauthorized )

                      %delete              = cond #( when delete_granted = abap_true then if_abap_behv=>auth-allowed else if_abap_behv=>auth-unauthorized )
                    )
        to result.
    endloop.


  endmethod.

  method is_update_granted.
    if has_before_image = abap_true.
      authority-check object 'ZRAP_OSTAT'
        id 'ZRAP_OSTAT' field travel_status
        id 'ACTVT' field '02'.
    else.
      authority-check object 'ZRAP_OSTAT'
        id 'ZRAP_OSTAT' dummy
        id 'ACTVT' field '02'.
    endif.
    update_granted = cond #( when sy-subrc = 0 then abap_true else abap_false ).

    " Simulate full access - for testing purposes only! Needs to be removed for a productive implementation.
    update_granted = abap_true.
  endmethod.

  method is_delete_granted.
    if has_before_image = abap_true.
      authority-check object 'ZRAP_OSTAT'
        id 'ZRAP_OSTAT' field travel_status
        id 'ACTVT' field '06'.
    else.
      authority-check object 'ZRAP_OSTAT'
        id 'ZRAP_OSTAT' dummy
        id 'ACTVT' field '06'.
    endif.
    delete_granted = cond #( when sy-subrc = 0 then abap_true else abap_false ).

    " Simulate full access - for testing purposes only! Needs to be removed for a productive implementation.
    delete_granted = abap_true.
  endmethod.

  method is_create_granted.
    authority-check object 'ZRAP_OSTAT'
      id 'ZRAP_OSTAT' dummy
      id 'ACTVT' field '01'.
    create_granted = cond #( when sy-subrc = 0 then abap_true else abap_false ).

    " Simulate full access - for testing purposes only! Needs to be removed for a productive implementation.
    create_granted = abap_true.
  endmethod.

endclass.
