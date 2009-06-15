#define THIS_FILE CBA\main\parseYAML
scriptName 'THIS_FILE';
// -----------------------------------------------------------------------------
//
// @description Parses a YAML file into a nexted array/Hash structure.
// 
// Parameters:
//   0: Name of Yaml formatted file to parse [String].
//
// Returns:
//   Data structure taken from the file, or nil if file had syntax errors.
//
// -----------------------------------------------------------------------------

#include "script_component.hpp"
#include "strings.inc.sqf"

#define YAML_MODE_STRING 0
#define YAML_MODE_ASSOC_KEY 1
#define YAML_MODE_ASSOC_VALUE 2
#define YAML_MODE_ARRAY 3

#define YAML_TYPE_UNKNOWN 0
#define YAML_TYPE_SCALAR 1
#define YAML_TYPE_ARRAY 2
#define YAML_TYPE_ASSOC 3

#define ASCII_YAML_COMMENT ASCII_HASH
#define ASCII_YAML_ASSOC ASCII_COLON
#define ASCII_YAML_ARRAY ASCII_MINUS

// -----------------------------------------------------------------------------

private "_raiseError";
_raiseError =
{
	PARAMS_4(_message,_yaml,_pos,_lines);
	
	private ["_errorBlock", "_i", "_lastLine", "_lastChar"];
	
	_lastLine = _lines select ((count _lines) - 1);
	_lastChar = _lastLine select ((count _lastLine) - 1);
	_lastLine resize ((count _lastLine) - 1);
	
	PUSH(_lastLine,ASCII_VERTICAL_BAR);
	PUSH(_lastLine,ASCII_HASH);
	PUSH(_lastLine,ASCII_VERTICAL_BAR);
	PUSH(_lastLine,_lastChar);
	
	_pos = _pos + 1;
	while { _pos < (count _yaml) } do
	{
		_char = _yaml select _pos;
		
		if (_char in [ASCII_YAML_COMMENT, ASCII_CR, ASCII_NEWLINE]) exitWith {};
		
		PUSH(_lastLine,_char);
		
		_pos = _pos + 1;
	};
	
	_errorBlock = "";
	for [{ _i = 0 max ((count _lines) - 6) }, { _i < (count _lines)}, { _i = _i + 1 }] do
	{
		_errorBlock = _errorBlock + format ["\n%1: %2", _i + 1,
			toString (_lines select _i)];
	};
	
	_message = format ["%1, in ""%2"" at line %3:\n%4", _message,
		_file, count _lines, _errorBlock];
	
	[_message, "SPON Core YAML parse error"] call CBA_fnc_error;
};

private "_parse";
_parse =
{
	PARAMS_4(_yaml,_pos,_indent,_lines);
	
	private ["_error", "_currentIndent", "_key", "_value", "_return",
		"_mode", "_dataType", "_data"];
		
	_error = false;
	_currentIndent = _indent max 0;
	_key = [];
	_value = [];
	_return = false;
	_mode = YAML_MODE_STRING;
	_dataType = YAML_TYPE_UNKNOWN;
	// _data is initially undefined.
	
	TRACE_3("Parsing YAML data item",_currentIndent,_pos,count _lines);
	
	while { (_pos < ((count _yaml) - 1)) and (not _error) and (not _return) } do
	{
		_pos = _pos + 1;
		_char = _yaml select _pos;
		
		if (_char == ASCII_YAML_COMMENT) then
		{
			// Trim comments.
			while { not (_char in _lineBreaks) } do
			{
				_pos = _pos + 1;
				_char = _yaml select _pos;
			};
			
			_pos = _pos - 1; // Parse the newline normally.
		}
		else
		{
			if (_char in _lineBreaks) then
			{
				_currentIndent = 0;
				PUSH(_lines,[]);
			}
			else
			{
				PUSH(_lines select ((count _lines) - 1), _char);
			};
			
			switch (_mode) do
			{
				case YAML_MODE_ARRAY:
				{
					if (_char in _lineBreaks) then
					{
						_value = [toString _value] call CBA_fnc_trim;
						
						// If remainder of line is blank, assume
						// multi-line data.
						if (([_value] call SPON_stringLength) == 0) then
						{
							private ["_retVal"];
							
							_retVal = ([_yaml, _pos, _currentIndent,
								_lines] call _parse);
							EXPLODE_3(_retVal,_pos,_value,_error);
						};
						
						if (not _error) then
						{
							TRACE_1("Added Array element",_value);
							PUSH(_data,_value);
							_mode = YAML_MODE_STRING;
						};
					}
					else
					{
						PUSH(_value,_char);
					};
				};
				case YAML_MODE_ASSOC_KEY:
				{
					if (_char in _lineBreaks) then
					{
						["Unexpected new-line, when expecting ':'",
								_yaml, _pos, _lines] call _raiseError;
							_error = true;
					}
					else
					{
						switch (_char) do
						{
							case ASCII_YAML_ASSOC:
							{
								_key = [toString _key] call CBA_fnc_trim;
								_mode = YAML_MODE_ASSOC_VALUE;
							};
							default
							{
								PUSH(_key,_char);
							};
						};
					};
				};
				case YAML_MODE_ASSOC_VALUE:
				{
					if (_char in _lineBreaks) then
					{
						_value = [toString _value] call CBA_fnc_trim;
						
						// If remainder of line is blank, assume
						// multi-line data.
						if (([_value] call SPON_stringLength) == 0) then
						{
							private ["_retVal"];
							
							_retVal = ([_yaml, _pos, _currentIndent,
								_lines] call _parse);
							EXPLODE_3(_retVal,_pos,_value,_error);
						};
						
						if (not _error) then
						{
							TRACE_1("Added Assoc element",_value);
							[_data, _key, _value] call CBA_fnc_hashSet;
							_mode = YAML_MODE_STRING;
						};
					}
					else
					{
						PUSH(_value,_char);
					};
				};
				case YAML_MODE_STRING:
				{
					switch (_char) do
					{
						case ASCII_CR:
						{
							// Already dealt with.
						};
						case ASCII_NEWLINE:
						{
							// Already dealt with.
						};
						case ASCII_SPACE:
						{
							_currentIndent = _currentIndent + 1;
							TRACE_2("Indented",_indent,_currentIndent);
						};
						case ASCII_YAML_ASSOC:
						{
							["Can't start a line with ':'",
								_yaml, _pos, _lines] call _raiseError;
							_error = true;
						};
						case ASCII_YAML_ARRAY:
						{
							TRACE_2("Array element found",_indent,_currentIndent);
							
							if (_currentIndent > _indent) then
							{
								if (_dataType == YAML_TYPE_UNKNOWN) then
								{
									TRACE_2("Starting new Array",count _lines,_indent);
									
									_data = [];
									_dataType = YAML_TYPE_ARRAY;
									
									_indent = _currentIndent;
									
									_value = [];
									_mode = YAML_MODE_ARRAY;
								}
								else
								{
									TRACE_2("BLAH",_indent,_currentIndent);
									_error = true;
								};
							}
							else{if (_currentIndent < _indent) then
							{
								// Ignore and pass down the stack.
								TRACE_2("End of Array",count _lines,_indent);
								_pos = _pos - 1;
								_return = true;
							}
							else
							{
								if (_dataType == YAML_TYPE_ARRAY) then
								{
									TRACE_2("New element of Array",count _lines,_indent);
									_value = [];
									_mode = YAML_MODE_ARRAY;
								}
								else
								{
									TRACE_2("BLEH",_indent,_currentIndent);
									_error = true;
								};
							}; };
						};
						default // Anything else must be the start of an associative key.
						{
							if (_currentIndent > _indent) then
							{
								if (_dataType == YAML_TYPE_UNKNOWN) then
								{
									TRACE_2("Starting new Assoc",count _lines,_indent);
									
									_data = [] call CBA_fnc_hashCreate;
									_dataType = YAML_TYPE_ASSOC;
									
									_indent = _currentIndent;
									
									_key = [_char];
									_value = [];
									_mode = YAML_MODE_ASSOC_KEY;
								}
								else
								{
									TRACE_2("BLAH",_indent,_currentIndent);
									_error = true;
								};
							}
							else{if (_currentIndent < _indent) then
							{
								// Ignore and pass down the stack.
								TRACE_2("End of Assoc",count _lines,_indent);
								_pos = _pos - 1;
								_return = true;
							}
							else
							{
								if (_dataType == YAML_TYPE_ASSOC) then
								{
									TRACE_2("New element of Assoc",count _lines,_indent);
									_key = [_char];
									_value = [];
									_mode = YAML_MODE_ASSOC_KEY;
								}
								else
								{
									TRACE_2("BLEH",_indent,_currentIndent);
									_error = true;
								};
							}; };
						};	
					};
				};
			};
		};
	};
	
	TRACE_4("Parsed YAML data item",_indent,_pos,_error,count _lines);
	
	[_pos, _data, _error]; // Return.
};

// ----------------------------------------------------------------------------

PARAMS_1(_file);

private ["_yamlString", "_yaml", "_outerData", "_lineBreaks"];
_yamlString = loadFile _file;
_yaml = toArray _yamlString;

_lineBreaks = [ASCII_NEWLINE, ASCII_CR];

TRACE_2("Parsing YAML file",_file,count _yaml);

// Ensure input ends with a newline.
if (not ((_yaml select ((count _yaml) - 1)) in _lineBreaks)) then
{
	PUSH(_yaml,ASCII_NEWLINE);
};

_pos = -1;

_retVal = ([_yaml, _pos, -1, [[]]] call _parse);

EXPLODE_3(_retVal,_pos,_data,_error);

if (_error) then
{
	nil; // Return.
}
else
{
	_data; // Return.
};