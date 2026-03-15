--
-- Wesnoth Journey Log module (front-end)
--
-- codename Naia - Project Ethea phase 1 campaigns shared library
-- Copyright (C) 2024 - 2026 by Iris Morelle <iris@irydacea.me>
--
-- See COPYING for usage terms.
--

local T = wml.tag

-- #textdomain wesnoth-Naia
local _ = wesnoth.textdomain "wesnoth-Naia"

-- WARNING: enabling this exposes incomplete, untested or crash-prone
--          functionality!
local JOURNEYLOG_ALLOW_BROKEN_GARBAGE      = false

local JOURNEYLOG_UI_ENTRY_TOP_MARGIN       = 10

local JOURNEYLOG_UI_SCENARIO_ICON          = "help/closed_section.png"
local JOURNEYLOG_UI_SCENARIO_ICON_SELECTED = "help/open_section.png"
local JOURNEYLOG_UI_LORE_ICON              = "help/topic.png"

local JOURNEYLOG_UI_MAJOR_DIVIDER          = "misc/loadscreen_decor.png~BLEND(162, 127, 68, 1.0)"
local JOURNEYLOG_UI_MINOR_DIVIDER          = "misc/ui-gradient.png~BLEND(162, 127, 68, 1.0)"

local JOURNEYLOG_UI_BIO_PLACEHOLDER        = _ "No information is presently available."
local JOURNEYLOG_UI_RACE_PLACEHOLDER       = _ "race^?"
local JOURNEYLOG_UI_STATUS_PLACEHOLDER     = _ "chara_status^Living"
local JOURNEYLOG_UI_GROUPS_PLACEHOLDER     = _ "affiliation^None"
local JOURNEYLOG_UI_TITLES_PLACEHOLDER     = _ "additional_titles^None"

local ACH_ALL        = 1
local ACH_COMPLETE   = 2
local ACH_INCOMPLETE = 3

local EVENT_LABELS = {
	start       = _ "event^Preparing for combat",
	time_over   = _ "event^Combat over",

	attack      = _ "event^Confrontation",
	moveto      = _ "event^Location approached",

	last_breath = _ "event^Character’s last words",
	die         = _ "event^Character death",

	defeat      = _ "event^Defeat",
	victory     = _ "event^Victory",
}

local UI_TAB_LABELS = {
	_ "Journal",
	_ "Knowledge",
	_ "Achievements",
	_ "Map",
}

local BIO_STATUS_LABELS = {
	dead        = _ "chara_status^Deceased",
	missing     = _ "chara_status^Missing",
}

local journeylog_section_listdef = {
	T.row {
		T.column {
			T.toggle_panel {
				T.grid {
					T.row {
						T.column {
							T.spacer {
								width = 20,
								height = 10
							}
						},
						T.column {
							grow_factor = 1,
							border = "all",
							border_size = 5,
							T.label {
								id = "tab_label",
								wrap = true
							}
						},
						T.column {
							T.spacer {
								width = 20,
								height = 10
							}
						}
					}
				}
			}
		}
	}
}

local journeylog_section_listdata = {
	T.row {
		T.column {
			T.widget {
				id = "tab_label",
				label = UI_TAB_LABELS[1]
			}
		}
	},
	T.row {
		T.column {
			T.widget {
				id = "tab_label",
				label = UI_TAB_LABELS[2]
			}
		}
	},
	T.row {
		T.column {
			T.widget {
				id = "tab_label",
				label = UI_TAB_LABELS[3]
			}
		}
	},
	T.row {
		T.column {
			T.widget {
				id = "tab_label",
				label = UI_TAB_LABELS[4]
			}
		}
	},
	T.row {
		T.column {
			T.widget {
				id = "tab_label",
				label = UI_TAB_LABELS[5]
			}
		}
	}
}

local journeylog_scenarios_listdef = {
	-- TITLE
	T.row { T.column {
		vertical_grow = true,
		horizontal_grow = true,
		T.toggle_panel {
			definition = "fancy",
			T.grid {
				T.row {
					T.column {
						vertical_alignment = "top",
						grow_factor = 0,
						border = "top,left,bottom",
						border_size = 10,
						T.image {
							id = "scenario_icon"
						}
					},
					T.column {
						horizontal_grow = true,
						grow_factor = 1,
						border = "all",
						border_size = 10,
						T.label {
							id = "scenario_name",
							linked_group = "scenario_name_group"
						}
					}
					,
					T.column {
						vertical_alignment = "top",
						grow_factor = 0,
						border = "all",
						border_size = 10,
						T.label {
							id = "scenario_serial",
							definition = "gold_small",
							text_alignment = "left",
							linked_group = "scenario_serial_group"
						}
					}
				}
			}
		}
	}}
}

local journeylog_chara_img_display = {
	vertical_alignment = "top",
	T.grid {
		T.row {
			T.column {
				horizontal_alignment = "right",
				vertical_alignment = "top",
				border = "all",
				border_size = 5,
				T.button {
					id = "image",
					linked_group = "portrait_img_group",
					definition = "naia_journeylog_image_viewer_button_small"
				}
			},
			T.column {
				border = "right",
				border_size = 10,
				T.spacer {}
			}
		}
	}
}

local journeylog_chara_name_display_compact = {
	horizontal_alignment = "right",
	vertical_alignment = "top",
	grow_factor = 0,
	border = "all",
	border_size = 5,
	T.label {
		id = "chara_name",
		definition = "naia_journeylog_dialog_speaker_inline",
		linked_group = "portrait_img_group",
		text_alignment = "right",
		wrap = true
	}
}

local journeylog_chara_name_display = {
	horizontal_alignment = "left",
	border = "all",
	border_size = 5,
	T.label {
		id = "chara_name",
		definition = "naia_journeylog_dialog_speaker",
		linked_group = "message_text_group",
		wrap = true
	}
}

local journeylog_chara_msg_display = {
	grow_factor = 1,
	horizontal_alignment = "left",
	border = "all",
	border_size = 5,
	T.label {
		id = "chara_msg",
		definition = "naia_journeylog_dialog_line",
		linked_group = "message_text_group",
		wrap = true
	}
}

local journeylog_narrator_msg_display = {
	grow_factor = 1,
	horizontal_alignment = "right",
	border = "all",
	border_size = 5,
	T.label {
		id = "chara_msg",
		definition = "naia_journeylog_page",
		wrap = true
	}
}

local journeylog_user_msg_display = {
	horizontal_alignment = "left",
	border = "all",
	border_size = 5,
	T.label {
		id = "user_msg",
		definition = "gold",
		linked_group = "message_text_group",
		wrap = true
	}
}

local journeylog_msg_spacer_col = {
	border = "top",
	border_size = 10,
	T.spacer {}
}

local journeylog_messages_treedef = {
	id = "messages_tree",
	definition = "naia_journeylog_viewer",
	linked_group = "right_side_pane",
	horizontal_scrollbar_mode = "never",
	vertical_scrollbar_mode = "always",
	indentation_step_size = 0,

	T.node {
		id = "container",
		unfolded = true,
		T.node_definition {
			T.row {
				T.column {
					T.spacer {}
				}
			}
		}
	},

	T.node {
		id = "plain_message",
		T.node_definition {
			T.row {
				T.column {
					grow_factor = 1,
					T.grid {
						T.row {
							T.column(journeylog_chara_img_display),
							T.column {
								horizontal_grow = true,
								vertical_alignment = "top",
								T.grid {
									T.row {
										T.column(journeylog_chara_name_display)
									},
									T.row {
										T.column(journeylog_chara_msg_display)
									}
								}
							}
						}
					}
				}
			},
			T.row {
				T.column(journeylog_msg_spacer_col)
			}
		}
	},

	T.node {
		id = "plain_message_compact",
		T.node_definition {
			T.row {
				T.column(journeylog_chara_name_display_compact),
				T.column(journeylog_chara_msg_display)
			},
			T.row {
				T.column(journeylog_msg_spacer_col),
				T.column(journeylog_msg_spacer_col)
			}
		}
	},

	T.node {
		id = "narrator_message",
		T.node_definition {
			T.row {
				T.column { T.spacer {} },
				T.column(journeylog_narrator_msg_display)
			},
			T.row {
				T.column(journeylog_msg_spacer_col),
				T.column(journeylog_msg_spacer_col)
			}
		}
	},

	T.node {
		id = "message_with_input",
		T.node_definition {
			T.row {
				T.column {
					T.grid {
						T.row {
							T.column(journeylog_chara_img_display),
							T.column {
								horizontal_grow = true,
								vertical_alignment = "top",
								T.grid {
									T.row {
										T.column(journeylog_chara_name_display)
									},
									T.row {
										T.column(journeylog_chara_msg_display)
									},
									T.row {
										T.column(journeylog_user_msg_display)
									}
								}
							}
						}
					}
				}
			},
			T.row {
				T.column(journeylog_msg_spacer_col)
			}
		}
	},

	T.node {
		id = "message_with_input_compact",
		T.node_definition {
			T.row {
				T.column(journeylog_chara_name_display_compact),
				T.column {
					T.grid {
						T.row {
							T.column(journeylog_chara_msg_display)
						},
						T.row {
							T.column(journeylog_user_msg_display)
						}
					}
				}
			},
			T.row {
				T.column(journeylog_msg_spacer_col),
				T.column(journeylog_msg_spacer_col)
			}
		}
	},

	T.node {
		id = "message_block_separator",
		T.node_definition {
			T.row {
				T.column {
					grow_factor = 0,
					horizontal_alignment = "center",
					border = "bottom",
					border_size = 10,
					T.image {
						label = JOURNEYLOG_UI_MINOR_DIVIDER
					}
				}
			}
		}
	},

	T.node {
		id = "event_heading",
		T.node_definition {
			T.row {
				T.column {
					grow_factor = 0,
					horizontal_alignment = "center",
					border = "top",
					border_size = 5,
					T.label {
						id = "event",
						definition = "naia_journeylog_event_heading",
						text_alignment = "center"
					}
				}
			},
			T.row {
				T.column {
					grow_factor = 0,
					horizontal_alignment = "center",
					border = "bottom",
					border_size = 5,
					T.image {
						label = JOURNEYLOG_UI_MINOR_DIVIDER
					}
				}
			}
		}
	}
}

local journeylog_nav_treedef = {
	id = "archive_nav_tree",
	definition = "naia_journeylog_viewer",
	linked_group = "left_side_pane",
	horizontal_scrollbar_mode = "never",
	vertical_scrollbar_mode = "auto",
	indentation_step_size = 0,

	T.node {
		id = "header",
		unfolded = true,
		T.node_definition {
			T.row {
				T.column {
					horizontal_grow = true,
					grow_factor = 1,
					border = "top,left,right",
					border_size = 10,
					T.label {
						id = "tree_view_node_label",
						definition = "gold_small",
						text_alignment = "center"
					}
				},
			},
			T.row {
				T.column {
					grow_factor = 0,
					horizontal_alignment = "center",
					T.image {
						label = JOURNEYLOG_UI_MINOR_DIVIDER
					}
				}
			}
		}
	},

	T.node {
		id = "entry",
		unfolded = true,
		T.node_definition {
			T.row {
				T.column {
					horizontal_grow = true,
					grow_factor = 1,
					T.toggle_panel {
						id = "tree_view_node_label",
						definition = "fancy",
						T.grid {
							T.row {
								T.column {
									vertical_alignment = "top",
									grow_factor = 0,
									border = "top,left,bottom",
									border_size = 10,
									T.image {
										id = "archive_item_icon",
										label = JOURNEYLOG_UI_LORE_ICON,
									}
								},
								T.column {
									horizontal_grow = true,
									grow_factor = 1,
									border = "all",
									border_size = 10,
									T.label {
										id = "archive_item_label"
									}
								}
							}
						}
					}
				}
			}
		}
	}
}

local function chara_info_panel_field(id, label)
	if id == nil or label == nil then
		return {
			T.column { T.spacer {} },
			T.column { T.spacer {} }
		}
	end

	return {
		T.column {
			grow_factor = 0,
			border = "all",
			border_size = 5,
			horizontal_grow = true,
			vertical_alignment = "top",
			T.label {
				id = id .. "_heading",
				definition = "naia_journeylog_bio_label",
				-- TODO: crashes the game in 1.18 if the item is hidden
				--linked_group = "bio_info_group",
				label = tostring(label) .. ":",
				text_alignment = "right",
				wrap = true
			}
		},
		T.column {
			grow_factor = 1,
			border = "all",
			border_size = 5,
			horizontal_grow = true,
			vertical_alignment = "top",
			T.label {
				id = id,
				definition = "naia_journeylog_bio_text",
				label = "BIO_PLACEHOLDER",
				text_alignment = "left",
				wrap = true
			}
		}
	}
end

local journeylog_chara_info_panel = {
	T.row {
		T.column {
			grow_factor = 1,
			border = "top,bottom",
			border_size = 5,
			horizontal_grow = true,
			vertical_alignment = "top",
			T.grid {
				T.row(chara_info_panel_field("additional_titles", _ "Other titles")),
				T.row(chara_info_panel_field("affiliation",       _ "Affiliation")),
				T.row(chara_info_panel_field("status",            _ "Status")),
				T.row(chara_info_panel_field("race",              _ "Race")),
			}
		},
		T.column {
			grow_factor = 0,
			horizontal_alignment = "right",
			border = "all",
			border_size = 5,
			T.button {
				id = "chara_portrait",
				definition = "naia_journeylog_image_viewer_button"
			}
		}
	},
	T.row {
		T.column {
			T.spacer {
				height = JOURNEYLOG_UI_ENTRY_TOP_MARGIN
			}
		},
		T.column {
			T.spacer {}
		}
	}
}

local journeylog_archive_treedef = {
	id = "archive_entry",
	definition = "naia_journeylog_viewer",
	linked_group = "right_side_pane",
	horizontal_scrollbar_mode = "never",
	vertical_scrollbar_mode = "always",
	indentation_step_size = 0,

	T.node {
		id = "chara_profile",
		T.node_definition {
			T.row {
				T.column {
					horizontal_grow = true,
					T.grid {
						T.row {
							T.column {
								grow_factor = 1,
								horizontal_alignment = "left",
								border = "all",
								border_size = 5,
								T.label {
									id = "archive_entry_title",
									definition = "gold_large",
									label = "CHARA_NAME",
									wrap = true
								}
							},
							T.column {
								grow_factor = 0,
								horizontal_alignment = "right",
								border = "all",
								border_size = 5,
								T.button {
									id = "unit_type_help",
									definition = "action_about",
									label = _ "Unit Description",
									tooltip = _ "Opens the character’s unit description in the Help browser"
								}
							}
						}
					}
				}
			},
			T.row {
				T.column {
					horizontal_grow = true,
					T.grid(journeylog_chara_info_panel)
				}
			},
			T.row {
				T.column {
					horizontal_grow = true,
					border = "all",
					border_size = 5,
					T.label {
						id = "archive_entry_body",
						definition = "naia_journeylog_page",
						label = "CHARA_DESCRIPTION",
						wrap = true
					}
				}
			}
		}
	},

	T.node {
		id = "lore_entry",
		T.node_definition {
			T.row {
				T.column {
					horizontal_grow = true,
					border = "all",
					border_size = 5,
					T.label {
						id = "archive_entry_title",
						definition = "gold_large",
						label = "ENTRY_TITLE",
						wrap = true
					}
				}
			},
			T.row {
				T.column {
					grow_factor = 1,
					border = "top,bottom",
					border_size = 5,
					horizontal_grow = true,
					vertical_alignment = "top",
					T.grid {
						T.row(chara_info_panel_field("source", _ "record_source^From")),
					}
				},
			},
			T.row {
				T.column {
					horizontal_grow = true,
					border = "all",
					border_size = 5,
					T.label {
						id = "archive_entry_body",
						definition = "naia_journeylog_page",
						label = "ENTRY_TEXT",
						wrap = true
					}
				}
			}
		}
	},

	T.node {
		id = "recap_subsection",
		T.node_definition {
			T.row {
				T.column {
					grow_factor = 0,
					horizontal_alignment = "center",
					border = "top",
					border_size = 15,
					T.image {
						label = JOURNEYLOG_UI_MINOR_DIVIDER
					}
				}
			},
			T.row {
				T.column {
					horizontal_grow = true,
					border = "all",
					border_size = 5,
					T.label {
						id = "archive_entry_title",
						definition = "gold_large",
						label = "ENTRY_TITLE",
						wrap = true
					}
				}
			},
			T.row {
				T.column {
					horizontal_grow = true,
					T.spacer {
						height = 10
					}
				}
			},
			T.row {
				T.column {
					grow_factor = 1,
					horizontal_grow = true,
					T.panel {
						id = "character_quote",
						T.grid {
							T.row {
								T.column {
									T.spacer {
										height = 10
									}
								}
							},
							T.row {
								T.column {
									grow_factor = 1,
									horizontal_grow = true,
									border = "left,right",
									border_size = 5,
									T.label {
										id = "quote_text",
										definition = "naia_journeylog_page",
										label = "ENTRY_QUOTE",
										wrap = true,
									}
								}
							},
							T.row {
								T.column {
									grow_factor = 1,
									horizontal_grow = true,
									border = "left,right",
									border_size = 5,
									T.label {
										id = "quote_author",
										definition = "naia_journeylog_page",
										label = "QUOTE_AUTHOR",
										text_alignment = "right",
										wrap = true,
									}
								}
							},
							T.row {
								T.column {
									horizontal_grow = true,
									T.spacer {
										height = 10
									}
								}
							}
						}
					}
				}
			},
			T.row {
				T.column {
					horizontal_grow = true,
					border = "all",
					border_size = 5,
					T.label {
						id = "archive_entry_body",
						definition = "naia_journeylog_page",
						label = "ENTRY_TEXT",
						wrap = true
					}
				}
			}
		}
	}
}

local journeylog_dialoglog_grid = {
	T.row {
		grow_factor = 1,
		T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_alignment = "top",
			border = "all",
			border_size = 5,
			T.listbox {
				id = "scenario_list",
				definition = "naia_journeylog_listbox",
				linked_group = "left_side_pane",
				T.list_definition(journeylog_scenarios_listdef)
			}
		},
		T.column {
			grow_factor = 3,
			horizontal_alignment = "left",
			vertical_grow = true,
			border = "all",
			border_size = 5,
			T.panel {
				definition = "naia_journeylog_panel",
				T.grid {
					T.row {
						T.column {
							vertical_grow = true,
							border = "all",
							border_size = 5,
							T.tree_view(journeylog_messages_treedef)
						}
					}
				}
			}
		}
	}
}

local journeylog_archive_grid = {
	T.row {
		grow_factor = 1,
		T.column {
			grow_factor = 1,
			vertical_alignment = "top",
			T.grid {
				T.row {
					grow_factor = 1,
					T.column {
						horizontal_alignment = "left",
						vertical_alignment = "top",
						border = "all",
						border_size = 5,
						T.tree_view(journeylog_nav_treedef)
					}
				}
			}
		},
		T.column {
			grow_factor = 3,
			horizontal_alignment = "left",
			vertical_grow = true,
			border = "all",
			border_size = 5,
			T.panel {
				definition = "naia_journeylog_panel",
				T.grid {
					T.row {
						grow_factor = 1,
						T.column {
							vertical_grow = true,
							border = "all",
							border_size = 5,
							T.tree_view(journeylog_archive_treedef)
						}
					}
				}
			}
		}
	}
}

local function journeylog_achievements_node_factory(extra_row)
	if extra_row then
		extra_row = T.row {
			T.column(extra_row)
		}
	end

	return { T.row {
		T.column {
			grow_factor = 0,
			vertical_alignment = "top",
			border = "all",
			border_size = 10,
			T.image {
				id = "icon",
				linked_group = "achievement_icons"
			}
		},
		T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_alignment = "top",
			border = "top,bottom",
			border_size = 5,
			T.grid {
				linked_group = "achievement_entries",
				T.row {
					T.column {
						horizontal_grow = true,
						border = "all",
						border_size = 5,
						T.label {
							id = "name",
							definition = "naia_journeylog_achievement_title",
							label = "achievement name",
							wrap = true
						}
					}
				},
				T.row {
					T.column {
						horizontal_grow = true,
						border = "all",
						border_size = 5,
						T.label {
							id = "description",
							definition = "naia_journeylog_dialog_line",
							label = "achievement description",
							wrap = true
						}
					}
				},
				extra_row
			}
		}
	}}
end

local journeylog_achievements_treedef = {
	id = "achievement_list",
	definition = "naia_journeylog_viewer",
	linked_group = "right_side_pane",
	horizontal_scrollbar_mode = "never",
	vertical_scrollbar_mode = "always",
	indentation_step_size = 0,

	T.node {
		id = "achievement_simple",
		T.node_definition(journeylog_achievements_node_factory())
	},

	T.node {
		id = "achievement_counter",
		T.node_definition(journeylog_achievements_node_factory {
			horizontal_alignment = "left",
			T.grid {
				T.row {
					T.column {
						grow_factor = 1,
						border = "all",
						border_size = 5,
						T.progress_bar {
							id = "progress_bar",
							definition = "default_thin_achievements",
							linked_group = "achievement_progress_bar"
						}
					},
					T.column {
						grow_factor = 0,
						border = "all",
						border_size = 5,
						T.label {
							id = "progress_text",
							label = "progress",
							linked_group = "achievement_progress_text"
						}
					}
				}
			}
		})
	}
}

local journeylog_achievements_filter_listdef = {
	T.row { T.column {
		vertical_grow = true,
		horizontal_grow = true,
		T.toggle_panel {
			definition = "fancy",
			T.grid {
				T.row {
					T.column {
						-- This is here to make the achievement filter menu entries
						-- exactly as tall as the knowledge archive entries.
						-- Topic icon is 24px tall, top/bottom margin are 10px each.
						T.spacer {
							height = 24 + 2 * 10
						}
					},
					T.column {
						horizontal_grow = true,
						grow_factor = 1,
						border = "all",
						border_size = 10,
						T.label {
							id = "label"
						}
					}
				}
			}
		}
	}}
}

local journeylog_achievements_grid = {
	T.row {
		grow_factor = 1,
		T.column {
			grow_factor = 1,
			vertical_alignment = "top",
			border = "all",
			border_size = 5,
			T.grid {
				linked_group = "left_side_pane",
				T.row {
					grow_factor = 1,
					T.column {
						horizontal_grow = true,
						grow_factor = 1,
						border = "top,left,right",
						border_size = 10,
						T.label {
							definition = "gold_small",
							label = _ "achievements^Filter",
							text_alignment = "center"
						}
					},
				},
				T.row {
					grow_factor = 0,
					T.column {
						grow_factor = 0,
						horizontal_alignment = "center",
						T.image {
							label = JOURNEYLOG_UI_MINOR_DIVIDER
						}
					}
				},
				T.row {
					grow_factor = 1,
					T.column {
						horizontal_grow = true,
						vertical_alignment = "top",
						T.listbox {
							id = "achievements_filter",
							definition = "naia_journeylog_listbox",
							T.list_definition(journeylog_achievements_filter_listdef),
							T.list_data {
								T.row {
									T.column {
										T.widget {
											id = "label",
											label = _ "achievements^All"
										}
									}
								},
								T.row {
									T.column {
										T.widget {
											id = "label",
											label = _ "achievements^Complete"
										}
									}
								},
								T.row {
									T.column {
										T.widget {
											id = "label",
											label = _ "achievements^Incomplete"
										}
									}
								}
							}
						}
					}
				},
				T.row {
					grow_factor = 1,
					T.column {
						horizontal_grow = true,
						grow_factor = 1,
						border = "top,left,right",
						border_size = 10,
						T.label {
							definition = "gold_small",
							label = _ "achievements^Progress",
							text_alignment = "center"
						}
					},
				},
				T.row {
					grow_factor = 0,
					T.column {
						grow_factor = 0,
						horizontal_alignment = "center",
						T.image {
							label = JOURNEYLOG_UI_MINOR_DIVIDER
						}
					}
				},
				T.row {
					grow_factor = 1,
					T.column {
						horizontal_grow = true,
						grow_factor = 1,
						border = "top,left,right",
						border_size = 10,
						T.progress_bar {
							id = "achievements_overall_bar",
							definition = "naia_journeylog_achievements_overall_progress"
						}
					}
				},
				T.row {
					grow_factor = 1,
					T.column {
						horizontal_grow = true,
						grow_factor = 1,
						border = "all",
						border_size = 10,
						T.label {
							id = "achievements_overall_text",
							label = "9999/9999",
							text_alignment = "right"
						}
					}
				}
			}
		},
		T.column {
			grow_factor = 1,
			horizontal_grow = false,
			vertical_grow = true,
			border = "all",
			border_size = 5,

			T.panel {
				definition = "naia_journeylog_panel",
				T.grid {
					T.row {
						grow_factor = 1,
						T.column {
							vertical_grow = true,
							border = "all",
							border_size = 5,
							T.tree_view(journeylog_achievements_treedef)
						}
					}
				}
			}
		}
	}
}

local journeylog_map_grid = {
    T.row {
        grow_factor = 1,
        T.column {
            horizontal_grow = true,
            vertical_grow = true,
            border = "all",
            border_size = 5,

            T.panel {
                id = "map_panel",
                definition = "naia_journeylog_panel_map",

                T.grid {
                    T.row {
                        grow_factor = 1,
                        T.column {
                            horizontal_grow = true,
                            vertical_grow = true,

                            T.label {
								id = "nightmare_text",
								definition = "naia_journeylog_page",
								wrap = true,
								text_alignment = "center",
							}
                        }
                    }
                }
            }
        }
    }
}

local journeylog_nightmare_grid = {
	T.row {
		grow_factor = 1,
		T.column {
			grow_factor = 1,
			horizontal_grow = true,
			vertical_grow = true,
			border = "all",
			border_size = 5,

			T.panel {
				definition = "naia_journeylog_panel",
				T.grid {
					T.row {
						grow_factor = 1,
						T.column {
							vertical_alignment = "center",
							border = "all",
							border_size = 5,
							T.label {
								id = "nightmare_text",
								definition = "naia_journeylog_page",
								wrap = true,
								text_alignment = "center",
							}
						}
					}
				}
			}
		}
	}
}

local journeylog_dlg = {
	definition = "naia_journeylog",

	automatic_placement = false,
	x = 0,
	y = 0,
	width = "(screen_width)",
	height = "(screen_height)",

	T.helptip { id = "tooltip" },
	T.tooltip { id = "tooltip" },

	T.linked_group {
		id = "scenario_name_group",
		fixed_width = true
	},

	T.linked_group {
		id = "scenario_serial_group",
		fixed_width = true
	},

	T.linked_group {
		id = "portrait_img_group",
		fixed_width = true
	},

	T.linked_group {
		id = "message_text_group",
		fixed_width = true
	},

	T.linked_group {
		id = "bio_info_group",
		fixed_width = true
	},

	T.linked_group {
		id = "achievement_icons",
		fixed_width = true,
		fixed_height = true,
	},

	T.linked_group {
		id = "achievement_entries",
		fixed_width = true,
	},

	T.linked_group {
		id = "achievement_progress_bar",
		fixed_width = true,
	},

	T.linked_group {
		id = "achievement_progress_text",
		fixed_width = true,
	},

	T.linked_group {
		id = "left_side_pane",
		fixed_width = true
	},

	T.linked_group {
		id = "right_side_pane",
		fixed_width = true
	},

	T.grid {
		T.row {
			grow_factor = 0,
			T.column {
				grow_factor = 1,
				horizontal_grow = true,
				vertical_alignment = "top",
				T.stacked_widget {
					T.layer {
						T.row {
							T.column {
								horizontal_alignment = "center",
								border = "top,left,right",
								border_size = 5,
								T.label {
									id = "title",
									definition = "title",
									label = "<DIALOG_TITLE>"
								}
							}
						},
						T.row {
							T.column {
								horizontal_alignment = "center",
								border = "all",
								border_size = 5,
								T.image {
									label = JOURNEYLOG_UI_MAJOR_DIVIDER
								}
							}
						}
					},
					T.layer {
						T.row {
							T.column {
								horizontal_alignment = "left",
								vertical_alignment = "top",
								T.grid {
									T.row {
										T.column {
											border = "all",
											border_size = 5,
											T.horizontal_listbox {
												id = "log_section_selector",
												T.list_definition(journeylog_section_listdef),
												T.list_data(journeylog_section_listdata)
											}
										}
									}
								}
							},
							T.column {
								horizontal_alignment = "right",
								vertical_alignment = "top",
								border = "all",
								border_size = 5,
								T.text_box {
									id = "search_box",
									hint_text = _ "Search",
									hint_image = "icons/action/zoomdefault_25.png~FL(horiz)~CS(-80,-90,-100)"
								}
							}
						}
					}
				}
			}
		},
		T.row {
			grow_factor = 1,
			T.column {
				horizontal_alignment = "center",
				vertical_grow = true,
				T.stacked_widget {
                	id = "tabs_container",
                	T.layer(journeylog_dialoglog_grid),
                	T.layer(journeylog_archive_grid),
                	T.layer(journeylog_achievements_grid),
                	T.layer(journeylog_map_grid),
                }
			}
		},
		T.row {
			grow_factor = 0,
			T.column {
				horizontal_grow = true,
				vertical_alignment = "bottom",
				border = "top",
				border_size = 5,
				T.grid {
					T.row {
						T.column {
							horizontal_alignment = "left",
							border = "all",
							border_size = 5,
							T.button {
								id = "campaigns_menu",
								label = _ "<unknown campaign>",
								tooltip = _ "Select the campaign to display",
								linked_group = "left_side_pane"
							}
						},
						T.column {
							grow_factor = 1,
							horizontal_alignment = "right",
							T.grid {
								T.row {
									grow_factor = 0,
									T.column {
										grow_factor = 0,
										horizontal_alignment = "right",
										border = "all",
										border_size = 5,
										T.toggle_button {
											id = "hidden_achievements",
											label = _ "Hidden achievements",
										}
									},
									T.column {
										grow_factor = 0,
										horizontal_alignment = "right",
										border = "all",
										border_size = 5,
										T.toggle_button {
											id = "compact_view",
											label = _ "Compact view",
										}
									},
									T.column {
										T.spacer {
											width = 30
										}
									},
									T.column {
										grow_factor = 0,
										horizontal_alignment = "right",
										border = "all",
										border_size = 5,
										T.button {
											id = "ok",
											label = "Close"
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}

local image_viewer_dlg = {
	definition = "message",
	maximum_width = 800,
	maximum_height = 600,
	click_dismiss = true,

	automatic_placement = false,

	x = "(min(max(0, mouse_x - window_width / 2), screen_width - window_width))",
	y = "(min(max(0, mouse_y - window_height / 2), screen_height - window_height))",
	width = "(if(window_width > 0, window_width, screen_width))",
	height = "(if(window_height > 0, window_height, screen_height))",

	T.helptip { id = "tooltip" },
	T.tooltip { id = "tooltip" },

	T.grid {
		T.row {
			T.column {
				border = "all",
				border_size = 5,
				T.image {
					id = "image"
				}
			}
		},
		T.row {
			T.column {
				border = "all",
				border_size = 5,
				T.label {
					id = "caption",
					wrap = true,
					definition = "gold"
				}
			}
		}
	}
}

-- Helper to create closures to handle portrait click events.
local function portrait_image_viewer(image, caption)
	return function()
		gui.show_dialog(image_viewer_dlg, function(self)
			self.image.label = image .. "~BG(0,0,0)"
			self.caption.marked_up_text = caption or ""
			if caption == nil then
				self.caption.visible = false
			end
		end)
	end
end

-- Helper to clear treeviews
-- Wesnoth 1.18 and 1.20 require different, mutually incompatible approaches
local function clear_treeview(target)
	target:remove_items_at(1, 0)
end

local function clean_campaign_name(text)
	return tostring(text):gsub("\n", " ")
end

local function is_empty_image(path)
	-- NOTE: This will also match images that are in reality painted over
	-- misc/blank-hex.png via ~BLIT(), but since there is pretty much no way
	-- anyone would use that for a legitimate character portrait, we do not
	-- need to support this particular case. For that matter, we don't need to
	-- support ~O() being used to zero-out an image's alpha channel either
	-- since no-one would be using this to blank out a portrait, surely.
	if path == nil or
	   path == "" or
	   tostring(path):match("^misc/blank%-hex%.png")
	then
		return true
	else
		return false
	end
end

local initial_tab = 1
local global_compact_view = false

-- BEGIN: FUNCTIONALITY SPECIFIC TO AFTER THE STORM EPISODE 3 SCENARIO 9

local journeylog_ui_dream_message     = "default"
local journeylog_ui_dream_color       = "default"
local journeylog_ui_dream_size        = "default"

function journeylog_ui_in_dream_sequence()
	if wesnoth.scenario.type == "scenario" and
	   wesnoth.scenario.campaign.id == "After_the_Storm_III" and
	   wesnoth.scenario.id == "09_Dark_Depths" and
	   wml.variables.finale_b_part == 3
	then
		return true
	end

	return false
end

function wesnoth.wml_actions._journeylog_ui_ats_e3s9(cfg)
	journeylog_ui_dream_message = cfg.message or "default"
	-- Crossing our fingers the next two are valid pango values or "default"
	journeylog_ui_dream_color = cfg.color or "default"
	journeylog_ui_dream_size = cfg.size or "default"

	-- Install preload handler to ensure our configuration is restored when
	-- reloading saved games (could've used variables but this is sneakier)

	wesnoth.wml_actions.remove_event {
		id = "ats_e3s9_journeylog_game_load_hook"
	}
	wesnoth.wml_actions.event {
		id = "ats_e3s9_journeylog_game_load_hook",
		name = "preload",
		first_time_only = false,
		T._journeylog_ui_ats_e3s9 {
			message = journeylog_ui_dream_message,
			color   = journeylog_ui_dream_color,
			size    = journeylog_ui_dream_size,
		}
	}
end

local function journeylog_ui_dream_hook(self)
	local msg = journeylog_ui_dream_message

	if msg == "default" then
		msg = _ "― This functionality is currently unavailable ―"
	end
	if journeylog_ui_dream_color ~= "default" then
		msg = ("<span color='%s'>%s</span>"):format(journeylog_ui_dream_color, msg)
	end
	if journeylog_ui_dream_size ~= "default" then
		msg = ("<span size='%s'>%s</span>"):format(journeylog_ui_dream_size, msg)
	end

	self.nightmare_text.marked_up_text = msg
	--self.nightmare_text.marked_up_text = ("<span color='#a00' size='300%%'>%s</span>"):format( journeylog_ui_dream_message)
end

-- END: FUNCTIONALITY SPECIFIC TO AFTER THE STORM EPISODE 3 SCENARIO 9

function journeylog_ui()
	-- Retrieve compact mode flag from persistent store
	wesnoth.wml_actions.global_table {
		T.read {
			key = "_journeylog_ui_compact"
		}
	}
	global_compact_view = wml.variables._journeylog_ui_compact or global_compact_view
	-- Delete internal WML variable
	wml.variables._journeylog_ui_compact = nil

	local journal = {}
	local archive = {
		profiles = journeylog.retrieve_character_profiles(),
		world = journeylog.retrieve_world_lore(),
		recaps = journeylog.retrieve_story_recaps(),
	}

	local chara_group_start, world_group_start, recap_group_start = 0, 0, 0
	local current_campaign, current_scenario, current_page = 0, 0, 0
	-- These are collections of current container item refs for easier
	-- mass-manipulation (e.g. for filtering).
	local scenario_listbox_rows = {}
	-- For each entry, .message is a ref to the original journeylog message
	-- while .ui is a ref to the treeview node.
	local journey_view_rows = {}
	-- Content filter in use, as a list of words to match
	local current_filter = {}

	local function clear_journey_view(treeview)
		if #journey_view_rows > 0 then
			journey_view_rows = {}
			clear_treeview(treeview)
		end
	end

	local function journey_view_add_node(treeview, node_type, journey_msg)
		-- The dialog view uses an indirect approach where the treeview
		-- contains nodes that are in charge of containing the nodes with the
		-- true contents so that we can hide the latter by collapsing their
		-- parent nodes. This is essential since in 1.18, we cannot use the
		-- visible property on nodes without crashing the game.
		local container = treeview:add_item_of_type("container")
		local new_node = container:add_item_of_type(node_type)
		table.insert(journey_view_rows, {
			message = journey_msg,
			ui = new_node,
			parent = container,
			visible = function() return container.unfolded end,
			set_visible = function(value) container.unfolded = value end
		})
		return new_node
	end

	local function apply_journey_filter_row(row)
		if #current_filter == 0 then
			-- This is only relevant when this function is called during view
			-- rebuilds, because set_journey_filter() will manually bail and
			-- set all rows to visible if the filter is empty.
			return
		end

		if not row then
			-- Just syntactic sugar used when this is called during view
			-- rebuilds.
			row = journey_view_rows[#journey_view_rows]
			if not row then
				return
			end
		end

		if row.message then
			local contents = {
				row.message.speaker,
				row.message.message
			}

			local visible = false

			for j, tstring in pairs(contents) do
				if tstring then
					-- Unfortunately we need to deep-copy translatable strings
					-- in order to search through them...
					local sz = tostring(tstring):lower()
					for k, word in pairs(current_filter) do
						if sz:find(word, 1, true) then
							visible = true
							break
						end
					end

				end
			end

			row.set_visible(visible)
		end
	end

	local function set_journey_filter(self, search_terms)
		local clean_terms = search_terms or ""
		-- Trim leading and trailing whitespace
		clean_terms = clean_terms:trim()

		if #clean_terms == 0 then
			for i, row in ipairs(journey_view_rows) do
				row.set_visible(true)
			end
			return
		end

		current_filter = {}
		for word in search_terms:gmatch("[^%s]+") do
			table.insert(current_filter, word:lower())
		end

		-- Reapply the journey filter after-the-fact without requiring a full
		-- rebuild of the current journey view, which would be more expensive.
		for i, row in ipairs(journey_view_rows) do
			apply_journey_filter_row(row)
		end
	end

	local function show_journey(self, campaign_num, scenario_num, force)
		if not campaign_num then
			-- TODO: display UI placeholder
			return
		end

		if not force and campaign_num == current_campaign and scenario_num == current_scenario then
			return
		end

		if campaign_num > #journal then
			return
		end

		if not scenario_num then
			-- Presumably the last scenario on record is the scenario being
			-- played right now. (FIXME: maybe too optimistic an assumption?)
			scenario_num = #journal[campaign_num].scenarios
		end

		if scenario_num > #journal[campaign_num].scenarios then
			return
		end

		current_scenario = scenario_num

		local campaign_id = journal[campaign_num].id
		local journey = journal[campaign_num].scenarios[scenario_num]
		local scenario_id = journey.id

		if not journey.cache_built then
			-- Didn't cache this journey yet...
			local raw_journey = journeylog.read_scenario(campaign_id, scenario_id)

			for i, event_data in ipairs(raw_journey) do
				if i > 1 then
					table.insert(journey.messages, {
						event_name = event_data.event
					})
				end

				for j, msg in ipairs(event_data.messages) do
					-- We don't do anything fancy with messages yet
					table.insert(journey.messages, msg)
				end
			end

			journey.cache_built = true
		end

		-- Cache built, we can proceed with the UI display now

		local treeview = self.messages_tree
		clear_journey_view(treeview)

		for i, msg in ipairs(journey.messages) do
			if msg.event_name then
				local i18n_event_name = EVENT_LABELS[msg.event_name]

				if i18n_event_name then
					local event_heading = journey_view_add_node(treeview, "event_heading")
					event_heading.event.label = i18n_event_name
				else
					journey_view_add_node(treeview, "message_block_separator")
				end
			else
				local msg_display

				if not global_compact_view and not msg.is_narrator then
					if msg.choice == nil then
						msg_display = journey_view_add_node(treeview, "plain_message", msg)
					else
						msg_display = journey_view_add_node(treeview, "message_with_input", msg)
					end
				else
					if msg.is_narrator  then
						msg_display = journey_view_add_node(treeview, "narrator_message", msg)
					elseif msg.choice == nil then
						msg_display = journey_view_add_node(treeview, "plain_message_compact", msg)
					else
						msg_display = journey_view_add_node(treeview, "message_with_input_compact", msg)
					end
				end

				if not global_compact_view and not msg.is_narrator then
					if not is_empty_image(msg.image) then
						msg_display.image.label = msg.image
						msg_display.image.on_button_click = portrait_image_viewer(msg.image, msg.speaker)
					else
						msg_display.image.visible = "hidden"
					end
				end

				if not msg.is_narrator then
					if msg.speaker ~= nil then
						msg_display.chara_name.marked_up_text = msg.speaker
					else
						msg_display.chara_name.visible = "hidden"
					end
				end

				if msg.message ~= nil then
					if not msg.is_narrator then
						msg_display.chara_msg.marked_up_text = msg.message
					else
						msg_display.chara_msg.marked_up_text = ("<span color='#baac7d'>%s</span>"):format(msg.message)
					end
				end
			end

			apply_journey_filter_row()
		end
	end

	local function set_journey_compact_view(self, value)
		global_compact_view = value
		show_journey(self, current_campaign, current_scenario, true)
	end

	local function update_scenario_icon(self)
		if self.scenario_list.selected_index ~= current_scenario then
			scenario_listbox_rows[current_scenario].scenario_icon.label = JOURNEYLOG_UI_SCENARIO_ICON
		end

		scenario_listbox_rows[self.scenario_list.selected_index].scenario_icon.label = JOURNEYLOG_UI_SCENARIO_ICON_SELECTED
	end

	local function bio_race_name_helper(race_id, gender_id)
		local gender = gender_id
		if not gender or gender == "unknown" then
			-- NOTE: Wesnoth 1.18 does not have a concept of an unknown gender
			gender = "male"
		end

		local race = wesnoth.races[race_id]

		if race then
			if gender == "female" then
				-- TODO: Wesnoth 1.18 does not offer female_name as a first-class
				--       citizen, why?
				return race.__cfg.female_name
			end

			return race.name
		end

		return JOURNEYLOG_UI_RACE_PLACEHOLDER
	end

	local function bio_status_helper(status)
		return BIO_STATUS_LABELS[status] or JOURNEYLOG_UI_STATUS_PLACEHOLDER
	end

	local function show_chara_bio(self, index)
		if not index or index > #archive.profiles then
			self.archive_entry.visible = false
			return
		end

		local profile = archive.profiles[index]

		if not profile then
			return
		end

		clear_treeview(self.archive_entry)

		local page = self.archive_entry:add_item_of_type("chara_profile")

		page.archive_entry_title.marked_up_text = ("<big>%s</big>"):format(profile.name)
		page.archive_entry_body.marked_up_text = transform_markup(profile.description) or JOURNEYLOG_UI_BIO_PLACEHOLDER

		page.chara_portrait.label = profile.portrait or ""
		page.race.marked_up_text = bio_race_name_helper(profile.race, profile.gender)
		page.status.marked_up_text = bio_status_helper(profile.status)
		page.affiliation.marked_up_text = profile.affiliation or JOURNEYLOG_UI_GROUPS_PLACEHOLDER
		page.additional_titles.marked_up_text = profile.additional_titles or JOURNEYLOG_UI_TITLES_PLACEHOLDER

		-- FIXME: Wesnoth 1.18 does not appear to support setting .visible on grids
		--        in Lua even though it is supported in C++

		if not profile.status then
			page.status.visible = false
			page.status_heading.visible = false
		end

		if not profile.additional_titles then
			page.additional_titles.visible = false
			page.additional_titles_heading.visible = false
		end

		if not profile.portrait then
			page.chara_portrait.visible = false
		else
			page.chara_portrait.on_button_click = portrait_image_viewer(profile.portrait, profile.name)
		end

		if not profile.help_unit_type then
			page.unit_type_help.visible = false
		else
			page.unit_type_help.on_button_click = function()
				gui.show_help(("unit_%s"):format(profile.help_unit_type))
			end
		end
	end

	local function show_world_lore_entry(self, index)
		if not index or index > #archive.world then
			self.archive_entry.visible = false
			return
		end

		local entry = archive.world[index]

		if not entry then
			return
		end

		clear_treeview(self.archive_entry)

		local page = self.archive_entry:add_item_of_type("lore_entry")

		page.archive_entry_title.marked_up_text = ("<big>%s</big>"):format(entry.title)
		page.archive_entry_body.marked_up_text = transform_markup(entry.text) or JOURNEYLOG_UI_BIO_PLACEHOLDER

		local source = entry.source
		if source then
			if type(source) == "string" then
				-- If not userdata, then this might (or might not) be the id
				-- of an existing scenario. In that case, retrieve the scenario
				-- name and use that instead.
				local info = journeylog.retrieve_scenario_info(source, nil, false)
				if info ~= nil then
					source = ("<i>%s</i> (%s)"):format(info.label, info.mnemonic)
				end
			end
			page.source.marked_up_text = source
		else
			page.source.visible = false
			page.source_heading.visible = false
		end

		-- HACK: work around layout bug in Wesnoth 1.18 that causes the entry
		-- display to often have unexpectedly short widgets when repopulated
		-- at first, resulting in most text being vertically cut off.
		self.archive_entry.visible = "hidden"
		self.archive_entry.visible = true
	end

	local function show_recap_entry(self, index)
		if not index or index > #archive.recaps then
			self.archive_entry.visible = false
			return
		end

		local entry = archive.recaps[index]

		if not entry then
			return
		end

		clear_treeview(self.archive_entry)

		local prologue = self.archive_entry:add_item_of_type("lore_entry")

		prologue.archive_entry_title.marked_up_text = ("<big>%s</big>"):format(entry.title)
		prologue.archive_entry_body.marked_up_text = transform_markup(entry.text) or JOURNEYLOG_UI_BIO_PLACEHOLDER

		prologue.source.visible = false
		prologue.source_heading.visible = false

		-- NOTE: There is a stupid bug in Wesnoth 1.18 that causes labels with a large
		-- height to get visually squashed as the user scrolls their container down. In
		-- order to avoid the occurrence of this, we actually create separate tree nodes
		-- (thus separate labels) holding the contents of the individual sections. We
		-- probably need to document this limitation somewhere more visible, since it
		-- follows that WML authors also have to take special care not to let a single
		-- prologue or section take up too many lines!

		for i, section_data in ipairs(entry.sections) do
			local section = self.archive_entry:add_item_of_type("recap_subsection")

			section.archive_entry_title.marked_up_text = ("%s"):format(section_data.title)
			section.archive_entry_body.marked_up_text = transform_markup(section_data.text) or JOURNEYLOG_UI_BIO_PLACEHOLDER

			if section_data.quote ~= nil then
				local quote_color = '#baac7d'
				section.quote_text.marked_up_text = (
					_ "character_quote_text_format^<span style='italic' color='%s'>“%s”</span>"
				):format(quote_color, section_data.quote)
				if section_data.quote_author ~= nil then
					section.quote_author.marked_up_text = (
						_ "character_quote_author_format^<span size='smaller' color='%s'>⎯ %s</span>"
					):format(quote_color, section_data.quote_author)
				else
					section.quote_author.visible = false
				end
			else
				section.character_quote.visible = false
			end
		end

		-- HACK: work around layout bug in Wesnoth 1.18 that causes the entry
		-- display to often have unexpectedly short widgets when repopulated
		-- at first, resulting in most text being vertically cut off.
		self.archive_entry.visible = "hidden"
		self.archive_entry.visible = true
	end

	local function make_nav_header(self, label)
		local header = self.archive_nav_tree:add_item_of_type("header")
		header.tree_view_node_label.label = label
	end

	local function populate_lore_entry_list(self)
		clear_treeview(self.archive_nav_tree)

		local j = 2 -- skip header

		if #archive.profiles > 0 then
			make_nav_header(self, _ "archive_section^People")
			chara_group_start = j
			for i, profile in ipairs(archive.profiles) do
				local archive_item = self.archive_nav_tree:add_item_of_type("entry")
				archive_item.archive_item_label.label = profile.name
				j = j + 1
			end
		end

		if #archive.world > 0 then
			j = j + 1 -- skip header
			make_nav_header(self, _ "archive_section^World")
			world_group_start = j
			for i, entry in ipairs(archive.world) do
				local archive_item = self.archive_nav_tree:add_item_of_type("entry")
				archive_item.archive_item_label.label = entry.title
				j = j + 1
			end
		end

		if #archive.recaps > 0 then
			j = j + 1 -- skip header
			make_nav_header(self, _ "archive_section^Recaps")
			recap_group_start = j
			for i, entry in ipairs(archive.recaps) do
				local archive_item = self.archive_nav_tree:add_item_of_type("entry")
				archive_item.archive_item_label.label = entry.title
				j = j + 1
			end
		end
	end

	local function show_archive_item(self, path, force)
		if path == nil then
			path = { 2 }
			force = true
		end

		if not force and path[1] == current_page then
			return
		end

		local index = path[1]

		if recap_group_start > 0 and index >= recap_group_start then
			index = 1 + index - recap_group_start
			show_recap_entry(self, index)
		elseif world_group_start > 0 and index >= world_group_start then
			index = 1 + index - world_group_start
			show_world_lore_entry(self, index)
		elseif chara_group_start > 0 and index >= chara_group_start then
			index = 1 + index - chara_group_start
			show_chara_bio(self, index)
		end

		current_page = path[1]
	end

	local achs = {}
	local achs_completed_pc = -1

	if journeylog.have_achievements() then
		achs = journeylog.enumerate_achievements()
	end

	local function populate_achievement_list(self)
		if #achs == 0 then
			return
		end

		clear_treeview(self.achievement_list)

		local filter = self.achievements_filter.selected_index
		local completed_count = 0

		for i, ach in ipairs(achs) do
			if ach.completed then
				completed_count = completed_count + 1
			end

			-- Apply filter first since we can't collapse nodes in 1.18
			if filter == ACH_COMPLETE and not ach.completed or
			   filter == ACH_INCOMPLETE and ach.completed
			then
				goto continue
			end

			-- Skip incomplete hidden achievements unless in debug mode
			if not ach.completed and ach.hidden and not self.hidden_achievements.selected then
				goto continue
			end

			local node_type = "achievement_simple"
			if ach.max_progress ~= 0 then
				node_type = "achievement_counter"
			end

			local node = self.achievement_list:add_item_of_type(node_type)

			local name = ach.name
			local desc = ach.description
			local icon = ach.icon

			if not ach.completed then
				name = ("<span alpha='66%%'>%s</span>"):format(name)
				desc = ("<span color='#777'>%s</span>"):format(desc)
				icon = ("%s~O(0.66)"):format(icon)

				if ach.hidden then
					name = ("<i>%s</i>"):format(name)
					desc = ("<i>%s</i>"):format(desc)
				end
			end

			node.name.marked_up_text        = name
			node.description.marked_up_text = desc
			node.icon.label                 = icon

			if ach.max_progress ~= 0 then
				local progress = ach.current_progress
				if progress == -1 then
					progress = ach.max_progress
				end
				node.progress_bar.percentage = mathx.round(100 * progress / ach.max_progress)
				node.progress_text.label = ("%d/%d"):format(progress, ach.max_progress)
				if not ach.completed then
					node.progress_text.marked_up_text = ("<span color='#777'>%d/%d</span>"):format(progress, ach.max_progress)
				end
			end

			::continue::
		end

		if achs_completed_pc == -1 then
			-- Set up overall progress bar. We only need to do this once ever.
			achs_completed_pc = 100 * completed_count / #achs

			self.achievements_overall_bar.percentage = mathx.round(achs_completed_pc)
			self.achievements_overall_text.label = ("%d/%d"):format(completed_count, #achs)
		end
	end

	local function show_tab(self, tab_num)
		if journeylog_ui_in_dream_sequence() then
			journeylog_ui_dream_hook(self)
			self.tabs_container.selected_index = 4
			self.compact_view.enabled = false
			self.search_box.enabled = false
			self.log_section_selector.visible = "invisible"
			return
		end

		self.tabs_container.selected_index = tab_num
		self.title.label = UI_TAB_LABELS[tab_num] or "OUT_OF_RANGE"

		if tab_num == 1 then
			self.scenario_list:focus()
			self.hidden_achievements.visible = false
			self.compact_view.visible = true
			self.search_box.visible = true
		elseif tab_num == 2 then
			self.archive_nav_tree:focus()
			self.hidden_achievements.visible = false
			self.compact_view.visible = false
			self.search_box.visible = false
		elseif tab_num == 3 then
			self.achievement_list:focus()
			self.hidden_achievements.visible = wesnoth.game_config.debug
			self.compact_view.visible = false
			self.search_box.visible = false
		elseif tab_num == 4 then
        	self.hidden_achievements.visible = false
        	self.compact_view.visible = false
        	self.search_box.visible = false
        elseif tab_num == 5 then
        	self.hidden_achievements.visible = false
        	self.compact_view.visible = false
        	self.search_box.visible = false
        end

		initial_tab = tab_num
	end

	local function preshow(self)
		for i, campaign in ipairs(journeylog.enumerate_campaigns()) do
			if campaign.id == wesnoth.scenario.campaign.id then
				current_campaign = i
				self.campaigns_menu.label = clean_campaign_name(campaign.name)
			end

			local campaign_journey = {
				id = campaign.id,
				name = campaign.name,
				scenarios = {},
			}

			for j, scenario in ipairs(journeylog.enumerate_scenarios(campaign.id)) do
				if scenario.id == wesnoth.scenario.id then
					current_scenario = j
				end

				local runtime_info = journeylog.retrieve_scenario_info(scenario.id) or {}

				local scenario_journey = {
					id = scenario.id,
					-- Prefer the label from Naia runtime init as it may be more accurate
					-- than older information engraved by journeylog into saved games.
					name = runtime_info.label or scenario.name,
					messages = {},
					cache_built = false,
				}

				local scenario_list_item = self.scenario_list:add_item()

				scenario_list_item.scenario_name.label = runtime_info.label or scenario.name
				scenario_list_item.scenario_icon.label = JOURNEYLOG_UI_SCENARIO_ICON
				if runtime_info.mnemonic then
					scenario_list_item.scenario_serial.label = runtime_info.mnemonic
				end

				table.insert(scenario_listbox_rows, scenario_list_item)

				-- We do not retrieve messages until a later time because that
				-- will result in a lot of deep t_string copies in C++. Let the
				-- user trigger those on a per-scenario basis when selecting
				-- one in the interface, since most of the time they won't be
				-- walking through the entire campaign's dialogues anyway.

				table.insert(campaign_journey.scenarios, scenario_journey)
			end

			table.insert(journal, campaign_journey)
		end

		-- TODO: The campaigns menu causes the script to crash and also does
		-- not yet repopulate the scenario list.
		--self.campaigns_menu.enabled = #journeylog > 1

		-- HACK: Wesnoth 1.18 does not support runtime changes to the
		-- contents of [menu_button] in Lua, so we make do with
		-- gui.show_menu instead. Luckily, it should be pretty rare for
		-- this button to be visible and enabled in the first place, so we
		-- can tolerate the tackiness.
		self.campaigns_menu.on_button_click = function()
			local menu_table = {}
			for i, campaign in ipairs(journal) do
				table.insert(menu_table, {
					label = campaign.name
				})
			end

			local index = gui.show_menu(menu_table)
			if index > 0 then
				current_campaign = index
				self.campaigns_menu.label = clean_campaign_name(journal[index].name)
				show_journey(self, index, 0, true)
			end
		end

		self.compact_view.selected = global_compact_view

		self.scenario_list.selected_index = current_scenario
		update_scenario_icon(self)

		self.scenario_list.on_modified = function()
			update_scenario_icon(self)
			show_journey(self, current_campaign, self.scenario_list.selected_index)
		end

		self.search_box.on_modified = function()
			set_journey_filter(self, self.search_box.text)
		end

		self.compact_view.on_modified = function()
			set_journey_compact_view(self, self.compact_view.selected)
		end

		self.archive_nav_tree.on_modified = function()
			show_archive_item(self, self.archive_nav_tree.selected_item_path)
		end

		self.log_section_selector.on_modified = function()
			show_tab(self, self.log_section_selector.selected_index)
		end

		self.achievements_filter.on_modified = function()
			populate_achievement_list(self)
		end

		self.hidden_achievements.on_modified = function()
			populate_achievement_list(self)
		end

		if not JOURNEYLOG_ALLOW_BROKEN_GARBAGE then
			self.campaigns_menu.visible = false
		end

		-- Set the initial selection.
		show_journey(self, current_campaign, current_scenario, true)
		populate_lore_entry_list(self)
		show_archive_item(self)
		populate_achievement_list(self)

		show_tab(self, initial_tab)
		self.log_section_selector.selected_index = initial_tab

		self.title.visible = false
	end

	gui.show_dialog(journeylog_dlg, preshow)

	-- Save compact mode flag to persistent store
	wml.variables._journeylog_ui_compact = global_compact_view
	wesnoth.wml_actions.global_table {
		T.write {
			key = "_journeylog_ui_compact"
		}
	}
	-- Delete internal WML variable
	wml.variables._journeylog_ui_compact = nil
end

--
-- Displays the JourneyLog user interface.
--
-- Usage:
--
--   [journeylog]
--   [/journeylog]
--
function wesnoth.wml_actions.journeylog()
	-- [journeylog] does not modify the gamestate, so it does not require a
	-- synced context to run.
	wesnoth.sync.run_unsynced(function() journeylog_ui() end)
end

--
-- Create WML context menu items
--

wesnoth.wml_actions.set_menu_item {
	id = "naia:70_journeylog",
	description = _ "Journal",
	image = "icons/menu-journeylog.png",
	synced = false,
	T.default_hotkey {
		key = "j",
	},
	T.show_if {
		-- synced=false has the side effect that we can invoke the command
		-- at LITERALLY ANT TIME, including during event handling. Not sure if
		-- it's intentional, but we can deal with it by manually checking if
		-- the user has control of the UI
		T["lua"] {
			code = "return wesnoth.current.user_can_invoke_commands"
		}
	},
	T.command {
		T.journeylog {}
	}
}
