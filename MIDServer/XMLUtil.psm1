function createXmlDocument {
    return new-object System.Xml.XmlDocument
}

function createElement {
    param([System.Xml.XmlDocument]$xmlDocument, [string]$name, [string]$value = "")

    if (!$xmlDocument) {
        return $null
    }
    
    $newElement = $xmlDocument.createElement($name)
    $newElement.InnerText = $value
    return $newElement
}

function createElementWithAttribute {
    param([System.Xml.XmlDocument]$xmlDocument, [string]$name, [string]$attributeName, [string]$attributeValue)

    if (!$xmlDocument) {
        return $null;
    }
    
    $newElement = $xmlDocument.createElement($name);
    $newElement.SetAttribute($attributeName, $attributeValue);
    return $newElement
}

function addAttribute {
    param([System.Xml.XmlElement]$xmlElement, [string]$attributeName, [string]$attributeValue)
    
    $xmlElement.SetAttribute($attributeName, $attributeValue);
}

function getChild {
    param([System.Xml.XmlNode]$xmlNode, [string]$name)
    
    if (!$xmlNode.HasChildNodes) {
        return $null;
    }
    
    $children = $xmlNode.ChildNodes;
    foreach ($child in $children) {
        if ($child.Name -eq $name) {
            return $child;
        }
    }
    
    return $null;
}

function getChildWithNameAndAttribute {
    param([System.Xml.XmlNode]$xmlNode, [string]$name, [string]$attributeName, [string]$attributeValue)
    
    if (!$xmlNode.HasChildNodes) {
        return $null;
    }
    
    $children = $xmlNode.ChildNodes;
    foreach ($child in $children) {
        if ($child.Name -eq $name -and $child.Attributes.Count -ne 0) {
            $value = $child.Attributes.ItemOf($attributeName);

            if ($value -and $value.Value -eq $attributeValue) {
                return $child;
            }
        }
    }
    
    return $null;
}

function appendChild {
    param([System.Xml.XmlNode]$parent, [System.Xml.XmlNode]$child)
    
    if ($parent -and $child) {
        $ignore = $parent.appendChild($child)
    }
}

function getXmlString {
    param([System.Xml.XmlDocument]$xmlDocument)
    
    if (!$xmlDocument) {
        return ""
    }
        
    $stringWriter = new-object System.IO.StringWriter
    $xmlTextWriter = new-object System.Xml.XmlTextWriter($stringWriter)
    $xmlDocument.WriteTo($xmlTextWriter)
    return $stringWriter.toString()
}