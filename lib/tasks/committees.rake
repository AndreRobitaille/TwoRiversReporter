namespace :committees do
  desc "Update committee descriptions from canonical WordPress source"
  task update_descriptions: :environment do
    updates = {
      "City Council" => "Exercises all legislative and general ordinance powers as outlined in [Wisconsin Statutes §§ 64.01–64.15](https://docs.legis.wisconsin.gov/statutes/statutes/64), which establish the council-manager form of government.",
      "Advisory Recreation Board" => "Provides recommendations for maintaining and improving city parks and developing recreational programs and activities to enhance the quality of life for residents. Established under [Two Rivers Ordinance 2-5-6](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-6ADREBO).",
      "Board of Appeals" => "Reviews appeals when someone believes a city official has made a mistake in enforcing local rules or ordinances. Also handles special requests for exceptions to these rules. Established under [Wis. Stats. § 62.23(7)(e)](https://docs.legis.wisconsin.gov/statutes/statutes/62/i/23/7/e/7) and [Two Rivers Ordinance 2-5-2](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-2BOAP).",
      "Board of Canvassers" => "Checks, confirms, and officially approves election results to ensure they are accurate and valid. Established under [Wisconsin Statutes § 7.53](https://docs.legis.wisconsin.gov/statutes/statutes/7/ii/53).",
      "Business and Industrial Development Committee" => "Advises the city council, city manager, and plan commission on industrial development. Promotes the city's industrial advantages, collects data on suitable industries, and compiles information on areas suitable for development. Established under [Two Rivers Ordinance 2-5-10](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-10BUINDECOIN).",
      "Business Improvement District Board" => "Works to retain, expand, and assist businesses of all sizes and identifies and attracts new or relocating businesses to the City of Two Rivers.",
      "Committee on Aging" => "Identifies concerns of older citizens and makes recommendations to protect their well-being, rights, and quality of life. Advises the Advisory Recreation Board and city manager on senior citizen issues. Established under [Two Rivers Ordinance 2-5-11](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-11COAG).",
      "Community Development Authority" => "Leads efforts to eliminate blight, promote urban renewal, and oversee housing and redevelopment projects. Operates under [Wis. Stats. § 66.1335](https://docs.legis.wisconsin.gov/statutes/statutes/66/xiii/1335) and [Two Rivers Ordinance 2-5-7](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-7CODEAU).",
      "Environmental Advisory Board" => "Provides support to the public works committee of the city council, including advice and feedback on policies and initiatives related to environmental protection, sustainability, and resiliency. Established under [Two Rivers Ordinance 2-5-5](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-5ENADBO).",
      "Explore Two Rivers Board of Directors" => "Promotes travel to Two Rivers, mostly for overnight stays, as room tax monies must be used for that purpose. Operates as a nonprofit utilizing room tax revenues in compliance with [Wisconsin Statutes § 66.0615](https://docs.legis.wisconsin.gov/2009/statutes/statutes/66/vi/0615/1m/d).",
      "Library Board of Trustees" => "Oversees the management and policy development of the public library, ensuring free access to knowledge and information for all residents. Holds exclusive control over library funds, property, and staffing. Established under [Wisconsin Statutes Chapter 43](https://docs.legis.wisconsin.gov/statutes/statutes/43) and [Two Rivers Ordinance 2-5-8](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-8LIBO).",
      "Main Street Board of Directors" => "Non-profit board supported by property taxes through the Business Improvement District (BID). Local commercial property owners contribute through special assessments to fund downtown improvements including building facades, streetscaping, events, and business support.",
      "Personnel and Finance Committee" => "Oversees city personnel policies and financial matters, including budgets, salaries, and overall fiscal management.",
      "Plan Commission" => "Develops and adopts the city's comprehensive plan to guide physical development, ensuring coordinated and harmonious growth that promotes public health, safety, and general welfare. Reviews and makes recommendations on public buildings, land acquisitions, plats, and zoning matters. Established under [Wisconsin Statutes § 62.23](https://docs.legis.wisconsin.gov/statutes/statutes/62/i/23/) and [Two Rivers Ordinance 2-5-1](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-1CIPLCO).",
      "Police and Fire Commission" => "Oversees the appointment, promotion, discipline, and dismissal of the Police and Fire Chiefs and their subordinates, ensuring the effective and ethical operation of the city's police and fire departments. Established under [Wisconsin Statutes § 62.13](https://docs.legis.wisconsin.gov/statutes/statutes/62/i/13) and [Two Rivers Ordinance 2-5-3](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT2GOAD_CH2-5BOCOCO_S2-5-3POFICO).",
      "Public Utilities Committee" => "Provides oversight and guidance on city utility operations, including water, sewer, and electricity, ensuring reliable and efficient services for residents.",
      "Public Works Committee" => "Reviews and advises on infrastructure projects, maintenance of city facilities, and public works operations such as roads, drainage, and sanitation.",
      "Room Tax Commission" => "Manages and allocates room tax revenues collected from lodging facilities within the city. Ensures these funds are used to promote tourism, attract visitors, and support local economic development in compliance with [Wisconsin Statutes § 66.0615](https://docs.legis.wisconsin.gov/statutes/statutes/66/VI/0615) and [Two Rivers Ordinance 6-11-9](https://library.municode.com/wi/two_rivers/codes/code_of_ordinances?nodeId=CD_ORD_TIT6LI_CH6-11ROLOTA_S6-11-9ROTACO).",
      "Zoning Board" => "Reviews zoning appeals, special exceptions, and variances. Handles cases where property owners seek permission to use their land in ways not normally allowed by the zoning code."
    }

    updated = 0
    updates.each do |name, desc|
      committee = Committee.find_by(name: name)
      if committee
        committee.update!(description: desc)
        updated += 1
        puts "  Updated: #{name}"
      else
        puts "  NOT FOUND: #{name}"
      end
    end
    puts "\nUpdated #{updated} of #{updates.size} committees."
  end
end
