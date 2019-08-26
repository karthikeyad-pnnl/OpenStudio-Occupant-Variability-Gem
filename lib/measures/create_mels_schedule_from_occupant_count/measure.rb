# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class CreateMELsScheduleFromOccupantCount < OpenStudio::Measure::ModelMeasure
  # Class variables

  @@v_space_args = Hash.new

  # Default file name set by occupancy simulator, change according in the future as needed.
  @@default_occupant_schedule_filename = 'OccSimulator_out_IDF.csv'
  @@mels_schedule_CSV_name = 'sch_MELs.csv'

  # The variables are used for the linear relation between people count and MELs
  @@a_office = 60.0 # MELs baseload: 60 W/max_person
  @@b_office = 140.0 # MELs dynamic load: 140 W/person

  @@a_conference = 20.0 # MELs baseload: 20 W/max_person
  @@b_conference = 140.0 # MELs dynamic load: 140 W/person

  @@minute_per_item = 10 # 10 minutes per simulation step

  # Standard space types for office rooms
  @@v_office_space_types = [
      'WholeBuilding - Sm Office',
      'WholeBuilding - Md Office',
      'WholeBuilding - Lg Office',
      'Office',
      'ClosedOffice',
      'OpenOffice',
      'SmallOffice - ClosedOffice',
      'SmallOffice - OpenOffice',
      'MediumOffice - ClosedOffice',
      'MediumOffice - OpenOffice',
      'LargeOffice - ClosedOffice',
      'LargeOffice - OpenOffice'
  ]
  # Standard space types for meeting rooms
  @@v_conference_space_types = [
      'Conference',
      'Classroom',
      'SmallOffice - Conference',
      'MediumOffice - Conference',
      'MediumOffice - Classroom',
      'LargeOffice - Conference'
  ]
  # Standard space types for auxiliary rooms
  @@v_auxiliary_space_types = [
      'OfficeLarge Data Center',
      'OfficeLarge Main Data Center',
      'SmallOffice - Elec/MechRoom',
      'MediumOffice - Elec/MechRoom',
      'LargeOffice - Elec/MechRoom'
  ]
  @@v_other_space_types = [
      'Office Attic',
      'BreakRoom',
      'Attic',
      'Plenum',
      'Corridor',
      'Lobby',
      'Elec/MechRoom',
      'Stair',
      'Restroom',
      'Dining',
      'Storage',
      'Locker',
      'Plenum Space Type',
      'SmallOffice - Corridor',
      'SmallOffice - Lobby',
      'SmallOffice - Attic',
      'SmallOffice - Restroom',
      'SmallOffice - Stair',
      'SmallOffice - Storage',
      'MediumOffice - Corridor',
      'MediumOffice - Dining',
      'MediumOffice - Restroom',
      'MediumOffice - Lobby',
      'MediumOffice - Storage',
      'MediumOffice - Stair',
      'LargeOffice - Corridor',
      'LargeOffice - Dining',
      'LargeOffice - Restroom',
      'LargeOffice - Lobby',
      'LargeOffice - Storage',
      'LargeOffice - Stair',
      ''
  ]

  # Available office tpye options for users in GUI
  @@office_type_names = [
      'Open-plan office',
      'Closed office'
  ]

  @@conference_room_type_names = [
      'Conference room',
      'Conference room example'
  ]

  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Create MELs Schedule from Occupant Count'
  end

  # human readable description
  def description
    return 'Replace this text with an explanation of what the measure does in terms that can be understood by a general building professional audience (building owners, architects, engineers, contractors, etc.).  This description will be used to create reports aimed at convincing the owner and/or design team to implement the measure in the actual building design.  For this reason, the description may include details about how the measure would be implemented, along with explanations of qualitative benefits associated with the measure.  It is good practice to include citations in the measure if the description is taken from a known source or if specific benefits are listed.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Replace this text with an explanation for the energy modeler specifically.  It should explain how the measure is modeled, including any requirements about how the baseline model must be set up, major assumptions, citations of references to applicable modeling resources, etc.  The energy modeler should be able to read this description and understand what changes the measure is making to the model and why these changes are being made.  Because the Modeler Description is written for an expert audience, using common abbreviations for brevity is good practice.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # CSV file path to cccupancy schedule generated by the Occupancy Simulator measure
    occ_schedule_dir = OpenStudio::Measure::OSArgument.makeStringArgument('occ_schedule_dir', false)
    occ_schedule_dir.setDisplayName('The path to the occupancy schedule CSV generated by the occupancy simulator measure.')
    occ_schedule_dir.setDescription('Enter the path if you want to use a specific occupancy schedule')
    occ_schedule_dir.setDefaultValue('')
    args << occ_schedule_dir

    # Space type choices
    space_type_chs = OpenStudio::StringVector.new
    office_space_type_chs = OpenStudio::StringVector.new
    meeting_space_type_chs = OpenStudio::StringVector.new
    other_space_type_chs = OpenStudio::StringVector.new

    @@office_type_names.each do |office_type_name|
      office_space_type_chs << office_type_name
    end

    @@conference_room_type_names.each do |conference_room_type_name|
      meeting_space_type_chs << conference_room_type_name
    end

    other_space_type_chs << "Auxiliary"
    other_space_type_chs << "Lobby"
    other_space_type_chs << "Corridor"
    other_space_type_chs << "Other"
    other_space_type_chs << "Plenum"

    v_space_types = model.getSpaceTypes

    i = 1
    # Loop through all space types, group spaces by their types
    v_space_types.each do |space_type|
      # Loop through all spaces of current space type
      # Puplate the valid options for each space depending on its space type
      if @@v_office_space_types.include? space_type.standardsSpaceType.to_s
        space_type_chs = office_space_type_chs
      elsif @@v_conference_space_types.include? space_type.standardsSpaceType.to_s
        space_type_chs = meeting_space_type_chs
      elsif @@v_other_space_types.include? space_type.standardsSpaceType.to_s
        space_type_chs = other_space_type_chs
        # else
        #   space_type_chs = other_space_type_chs
      end

      # Get arguments for each space
      v_current_spaces = space_type.spaces
      next if not v_current_spaces.size > 0
      v_current_spaces.each do |current_space|

        arg_name = current_space.nameString.gsub(' ', '-')
        @@v_space_args[current_space.nameString] = arg_name
        arg_temp = OpenStudio::Measure::OSArgument::makeChoiceArgument(arg_name, space_type_chs, true)
        arg_temp.setDisplayName("Space #{i}: " + current_space.nameString)

        # Conditionally set the default choice for the space
        if (@@v_office_space_types.include? space_type.standardsSpaceType.to_s)
          arg_temp.setDefaultValue("Open-plan office")
        elsif (@@v_conference_space_types.include? space_type.standardsSpaceType.to_s)
          arg_temp.setDefaultValue("Conference room")
        elsif (@@v_auxiliary_space_types.include? space_type.standardsSpaceType.to_s)
          arg_temp.setDefaultValue('Auxiliary')
        elsif (@@v_other_space_types.include? space_type.standardsSpaceType.to_s)
          # If the space type is not in standard space types
          arg_temp.setDefaultValue('Other')
        end
        args << arg_temp
        i += 1
      end
    end

    return args
  end

  def add_equip(model, space, schedule)
    # This function creates and adds OS:equip and OS:equip:Definition objects to a space

    space_name = space.name.to_s
    # New equip definition
    new_equip_def = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    new_equip_def.setDesignLevelCalculationMethod('Watts/Person', 1, 1)
    new_equip_def.setName(space_name + ' electric equipmendefinition')
    new_equip_def.setWattsperPerson(@@a_office + @@b_office) # !!!
    # new_equip_def.setFractionRadiant(0.7)
    # new_equip_def.setFractionVisible(0.2)

    # New electric equipment
    new_equip = OpenStudio::Model::ElectricEquipment.new(new_equip_def)
    new_equip.setName(space_name + ' electric equipment')
    new_equip.setSpace(space)
    new_equip.setSchedule(schedule)

    return model
  end

  def create_equip_sch_from_occupant_count(space_name, space_type, v_occ_n_count)
    # This function creates a electric equipment schedule based on the occupant count schedule
    # Delay is in minutes
    # Note: Be careful of the timestep format when updating the function
    v_temp = Array.new
    v_occ_n_count.each_with_index do |value_timestamp, i|
      # puts b * value_timestamp.to_f
      if @@office_type_names.include? space_type
        v_temp[i] = (@@a_office + @@b_office * value_timestamp.to_f) / (@@a_office + @@b_office)
      elsif @@conference_room_type_names.include? space_type
        v_temp[i] = (@@a_conference + @@b_conference * value_timestamp.to_f) / (@@a_conference + @@b_conference)
      end
    end
    return [space_name] + v_temp
  end

  def vcols_to_csv(v_cols, file_name = @@mels_schedule_CSV_name)
    # This function write an array of columns(arrays) into a CSV.
    # The first element of each column array is treated as the header of that column
    # Note: the column arrays in the v_cols should have the same length
    nrows = v_cols[0].length
    CSV.open(file_name, 'wb') do |csv|
      0.upto(nrows - 1) do |row|
        v_row = Array.new()
        v_cols.each do |v_col|
          v_row << v_col[row]
        end
        csv << v_row
      end
    end
  end

  def get_os_schedule_from_csv(file_name, model, schedule_name, col, skip_row)
    puts '---> Try to create schedule:file object...'
    file_name = File.realpath(file_name)
    raise "File '#{file_name}' does not exist" if !File.exists?(file_name)
    external_file = OpenStudio::Model::ExternalFile::getExternalFile(model, file_name)
    raise "ExternalFile for '#{file_name}' is not initialized" if external_file.empty?
    external_file = external_file.get
    schedule_file = OpenStudio::Model::ScheduleFile.new(external_file, col, skip_row)
    schedule_file.setName(schedule_name)
    return schedule_file
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    runner.registerInfo("Start to create electrical equipment measure from occupant schedule")

    ### get file directories
    model_temp_run_path = Dir.pwd + '/'
    model_temp_resources_path = File.expand_path("../../..", model_temp_run_path) + '/resources/' # where the occupancy schedule will be saved

    puts "start to get user input..."

    ### Get user selected electrical equipment space assumptions for each space
    v_space_types = model.getSpaceTypes
    i = 1
    equip_space_type_arg_vals = {}
    # Loop through all space types, group spaces by their types
    v_space_types.each do |space_type|
      # Loop through all spaces of current space type
      v_current_spaces = space_type.spaces
      next if not v_current_spaces.size > 0
      v_current_spaces.each do |current_space|
        equip_space_type_val = runner.getStringArgumentValue(@@v_space_args[current_space.nameString], user_arguments)
        equip_space_type_arg_vals[current_space.nameString] = equip_space_type_val
        i += 1
      end
    end

    puts equip_space_type_arg_vals

    ### Start creating new lighting schedules based on occupancy schedule
    occ_schedule_dir = runner.getStringArgumentValue('occ_schedule_dir', user_arguments)
    model_temp_run_path = Dir.pwd + '/'
    measure_root_path = File.dirname(__FILE__)


    if File.file?(occ_schedule_dir)
      csv_file = occ_schedule_dir
      puts 'Use user provided occupancy schedule file at: ' + csv_file.to_s
      runner.registerInitialCondition('Use default occupancy schedule file at: ' + csv_file.to_s)
    else
      # Check if schedule file at several places
      # 1. Default fils path when run with OSW in CLI
      csv_path_lookup_1 = File.expand_path("../..", measure_root_path) + "/files/#{@@default_occupant_schedule_filename}"
      puts '#' * 80
      puts "First lookup location: " + csv_path_lookup_1
      # 2. Default path when run with OpenStudio CLI
      csv_path_lookup_2 = File.expand_path("../..", model_temp_run_path) + "/files/#{@@default_occupant_schedule_filename}"
      puts '#' * 80
      puts "Second lookup location: " + csv_path_lookup_2
      # 3. Default path when run with OpenStudio GUI
      csv_path_lookup_3 = File.expand_path("../../..", model_temp_run_path) + "/resources/files/#{@@default_occupant_schedule_filename}"
      puts '#' * 80
      puts "Third lookup location: " + csv_path_lookup_3
      # 4. Generated files folder when run with rspec
      csv_path_lookup_4 = File.expand_path("..", model_temp_run_path) + "/generated_files/#{@@default_occupant_schedule_filename}"
      puts '#' * 80
      puts "Forth lookup location: " + csv_path_lookup_4


      if File.file?(csv_path_lookup_1)
        csv_file = csv_path_lookup_1
      elsif File.file?(csv_path_lookup_2)
        csv_file = csv_path_lookup_2
      elsif File.file?(csv_path_lookup_3)
        csv_file = csv_path_lookup_3
      elsif File.file?(csv_path_lookup_4)
        csv_file = csv_path_lookup_4      
      else
        csv_file = ''
      end
      puts 'Use default occupancy schedule file at: ' + csv_file.to_s
      runner.registerInitialCondition('Use default occupancy schedule file at: ' + csv_file.to_s)
    end

    ### Start creating new electrical equipment schedules based on occupancy schedule
    # Get the spaces with occupancy count schedule available
    v_spaces_occ_sch = File.readlines(csv_file)[3].split(',') # Room ID is saved in 4th row of the occ_sch file
    v_headers = Array.new
    v_spaces_occ_sch.each do |space_occ_sch|
      if (!['Room ID', 'Outdoor', 'Outside building'].include? space_occ_sch and !space_occ_sch.strip.empty?)
        v_headers << space_occ_sch
      end
    end
    v_headers = ["Time"] + v_headers

    # report initial condition of model
    runner.registerInitialCondition("The building has #{v_headers.length - 1} spaces with available occupant schedule file.")

    # Read the occupant count schedule file and clean it
    clean_csv = File.readlines(csv_file).drop(6).join
    csv_table_sch = CSV.parse(clean_csv, headers: true)
    new_csv_table = csv_table_sch.by_col!.delete_if do |column_name, column_values|
      !v_headers.include? column_name
    end

    runner.registerInfo("Successfully read occupant count schedule from CSV file.")
    runner.registerInfo("Creating new electrical equipment schedules...")

    # Create electrical equipment schedule based on the occupant count schedule
    v_cols = Array.new
    v_headers.each do |header|
      if header != 'Time'
        space_name = header
        space_type = equip_space_type_arg_vals[space_name]
        v_occ_n = new_csv_table.by_col![space_name]
        v_equip = create_equip_sch_from_occupant_count(space_name, space_type, v_occ_n)
        v_cols << v_equip
      end
    end

    runner.registerInfo("Writing new electrical equipment schedules to CSV file.")
    # Write new electrical equipment schedule file to CSV
    file_name_equip_sch = "#{model_temp_run_path}/#{@@mels_schedule_CSV_name}"
    vcols_to_csv(v_cols, file_name_equip_sch)

    # Add new electrical equipment schedule from the CSV file created
    runner.registerInfo("Adding new OS:Schedule:File objects to the model....")

    # Only remove the old equipment schedule for office and comference rooms
    runner.registerInfo("Removing old OS:ElectricEquipment and OS:ElectricEquipment:Definition for office and conference rooms.")
    # Remove old electric equipment definition objects for office and conference rooms
    v_space_types.each do |space_type|
      space_type.spaces.each do |space|
        selected_space_type = equip_space_type_arg_vals[space.name.to_s]
        if (@@office_type_names.include? selected_space_type) || (@@conference_room_type_names.include? selected_space_type)
          space_type.electricEquipment.each do |ee|
            puts 'Remove old electric equipment definition object: ' + ee.electricEquipmentDefinition.name.to_s
            ee.electricEquipmentDefinition.remove
          end
        end
      end
    end


    # Remove old electric equipment objects for office and conference rooms
    # Caution: the order of deletion matters
    v_space_types.each do |space_type|
      space_type.spaces.each do |space|
        selected_space_type = equip_space_type_arg_vals[space.name.to_s]
        if (@@office_type_names.include? selected_space_type) || (@@conference_room_type_names.include? selected_space_type)
          space_type.electricEquipment.each do |ee|
            puts 'Remove old electric equipment object ' + ee.name.to_s
            ee.remove
          end
        end
      end
    end

    runner.registerInfo("Adding new OS:ElectricEquipment and OS:ElectricEquipment:Definition for office and conference rooms.")
    # Add new schedules
    v_spaces = model.getSpaces
    v_spaces.each do |space|
      # puts space.name.to_s
      v_headers.each_with_index do |s_space_name, i|
        if s_space_name == space.name.to_s
          col = i
          temp_file_path = file_name_equip_sch
          sch_file_name = space.name.to_s + ' equip sch'
          scheduleFile = get_os_schedule_from_csv(model, temp_file_path, sch_file_name, col, skip_row = 1)
          # puts scheduleFile
          scheduleFile.setMinutesperItem(@@minute_per_item.to_s)
          model = add_equip(model, space, scheduleFile)
        end
      end
    end

    # report final condition of model
    runner.registerFinalCondition("Finished creating and adding new electrical equipment schedules for #{v_headers.length - 1} spaces.")

    return true
  end
end

# register the measure to be used by the application
CreateMELsScheduleFromOccupantCount.new.registerWithApplication
